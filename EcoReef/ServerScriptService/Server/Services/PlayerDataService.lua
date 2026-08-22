--[[
	================================================================
	ЭКОРИФ: Симулятор Спасения Океана
	================================================================
	Файл:         PlayerDataService
	Тип объекта:  ModuleScript
	Расположение: ServerScriptService → Server → Services → PlayerDataService

	НАЗНАЧЕНИЕ:
		Сердце сервера. Единственный модуль, которому разрешено
		работать с сохраняемыми данными игрока (через ProfileService).

		Отвечает за:
		  • Загрузку / автосохранение / освобождение профиля игрока
		  • Валюты: Coins (Монеты), EcoEnergy (Эко-энергия),
		    RebirthPoints (Rebirth-очки)
		  • Инвентарь существ (вид, редкость, мутация, уровень)
		  • Валидацию ВСЕХ значений перед записью в профиль

	ПРАВИЛА БЕЗОПАСНОСТИ (святые — нарушать нельзя):
		  1. Этот модуль живёт ТОЛЬКО на сервере. Клиент его не видит.
		  2. Функции модуля вызывают только серверные сервисы.
		     Клиент никогда не пишет в данные напрямую — только
		     просит сервер (через Remote), а сервер всё проверяет.
		  3. Любое число от клиента проверяется на тип, NaN,
		     бесконечность, отрицательность и целочисленность.
		  4. У каждого существа уникальный UId (GUID) — это основа
		     анти-дюпа в будущей системе трейда.

	ЗАВИСИМОСТИ:
		  ProfileService — ServerScriptService → Server → Packages
		  → ProfileService (ModuleScript, официальная библиотека,
		  https://github.com/MadStudioRoblox/ProfileService, MIT)

	Версия: 1.0 (Шаг 1 дорожной карты MVP)
	================================================================
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

-- ================================================================
-- ПОДКЛЮЧЕНИЕ ЗАВИСИМОСТЕЙ
-- ================================================================

-- script = ...Services.PlayerDataService
-- script.Parent = ...Services
-- script.Parent.Parent = ...Server
local ServerFolder = ServerScriptService:WaitForChild("Server")
local PackagesFolder = ServerFolder:WaitForChild("Packages")
local ProfileService = require(PackagesFolder:WaitForChild("ProfileService"))

local PlayerDataService = {}

-- ================================================================
-- КОНСТАНТЫ
-- ================================================================

-- Имя DataStore-хранилища. "V1" в конце — страховка: если однажды
-- структура данных изменится несовместимо, мы откроем "V2" и старые
-- сохранения игроков не пострадают.
local STORE_NAME = "EcoReef_PlayerData_V1"

-- Потолок любой валюты. Защита от переполнения и от читерских чисел
-- вида 1e308. 900 триллионов хватит с огромным запасом.
local MAX_CURRENCY = 9 * 10 ^ 14

-- Базовое число слотов инвентаря существ (геймпасс "+5 слотов"
-- будет ДОБАВЛЯТЬСЯ к этому числу в модуле монетизации).
local BASE_PET_SLOTS = 20

-- Белые списки. Всё, чего нет в этих списках, в профиль не пишется.
local CURRENCIES = {
	Coins = true,         -- Монеты (мягкая валюта: продажа мусора и существ)
	EcoEnergy = true,     -- Эко-энергия (переработка мусора; тратится на апгрейды)
	RebirthPoints = true, -- Rebirth-очки (твёрдая валюта престижа)
}

local RARITIES = {
	Common = true,      -- Обычный
	Rare = true,        -- Редкий
	Epic = true,        -- Эпик
	Legendary = true,   -- Легендарный
	Mythical = true,    -- Мифик
	Ancient = true,     -- Древний
}

local MUTATIONS = {
	None = true,            -- Обычный (без мутации)
	Shiny = true,           -- Блеск
	Bioluminescent = true,  -- Свечение
	Golden = true,          -- Золотой
	Toxic = true,           -- Токсичный (только в загрязнённых зонах)
	Rainbow = true,         -- Радужный
	Ancient = true,         -- Каменный (древний)
}

-- ================================================================
-- ШАБЛОН ПРОФИЛЯ НОВОГО ИГРОКА (DataTemplate)
-- ----------------------------------------------------------------
-- ProfileService при каждой загрузке «доливает» недостающие поля
-- из этого шаблона в старые сохранения (метод :Reconcile()).
-- Поэтому мы можем спокойно ДОБАВЛЯТЬ новые поля в шаблон —
-- у ветеранов игры они появятся автоматически, прогресс не потеряется.
-- УДАЛЯТЬ или ПЕРЕИМЕНОВЫТЬ поля нельзя — для этого есть миграции ниже.
-- ================================================================

local TEMPLATE = {
	-- ---------- Валюты ----------
	Coins = 0,
	EcoEnergy = 0,
	RebirthPoints = 0,
	Rebirths = 0, -- сколько раз игрок сделал Rebirth

	-- ---------- Инвентарь существ ----------
	-- Массив записей. Пример одной записи:
	-- {
	--     UId = "0f8c2a61-...(GUID)",
	--     Species = "Clownfish",
	--     Rarity = "Rare",
	--     Mutation = "Shiny",
	--     Level = 1,
	--     HatchedAt = 1712345678,
	--     Locked = false,
	-- }
	Creatures = {},
	BasePetSlots = BASE_PET_SLOTS,   -- слоты инвентаря (без учёта геймпассов)
	EquippedCreatures = {},          -- UId существ, поставленных в риф (пассивный доход, Шаг 4)

	-- ---------- Улучшения инструментов ----------
	-- Уровни апгрейдов: 0 = не куплен. Цены и эффекты — в UpgradesConfig (Шаг 2).
	Upgrades = {
		Capacity = 0,    -- Ёмкость вакуум-луча (сколько мусора уносит за рейс)
		Speed = 0,       -- Скорость передвижения и сбора
		Luck = 0,        -- Удача: шанс редких яиц и мутаций
		AutoCollect = 0, -- Автосбор (0 = выключен)
		Range = 0,       -- Радиус действия луча
	},

	-- ---------- Прогресс по зонам ----------
	-- Ключ зоны = ключ из ZonesConfig (Шаг 2). Храним ТОЛЬКО сырые
	-- счётчики — проценты очистки сервер посчитает сам (нельзя доверять клиенту).
	Zones = {
		Shallow = { -- Зона 1: Мелководье
			TrashCollected = 0,     -- сколько единиц мусора собрано
			RebirthsDone = 0,       -- сколько раз зону сбрасывали ребёртом (после этого паттерн мусора меняется)
			NestsCleared = 0,       -- сколько гнёзд очищено (для яиц)
		},
	},

	-- ---------- Статистика ----------
	Stats = {
		TotalTrashCollected = 0,
		TotalEggsHatched = 0,
		TotalCreaturesCaught = 0,
		PlayTimeSeconds = 0,
		FirstLogin = 0, -- os.time() при первом входе
		LastLogin = 0,
	},

	-- ---------- Покупки и настройки ----------
	Gamepasses = {}, -- { ["12345678"] = true } — дубликат факта покупки (источник истины — MarketplaceService)
	Settings = {
		MusicOn = true,
		SoundsOn = true,
	},

	-- ---------- Служебное ----------
	DataVersion = 1, -- версия структуры данных (для миграций, см. ниже)
}

-- ================================================================
-- МИГРАЦИИ СТАРЫХ СОХРАНЕНИЙ
-- ----------------------------------------------------------------
-- Reconcile умеет только ДОБАВЛЯТЬ missing-поля. Если поле нужно
-- переименовать или изменить структуру — пишем миграцию.
-- Номер миграции = новая версия DataVersion в профиле игрока.
-- Пример:
--   local MIGRATIONS = {
--       [2] = function(data)
--           data.NewCurrency = data.OldCurrency
--           data.OldCurrency = nil
--       end,
--   }
-- ================================================================

local MIGRATIONS = {} -- пока пусто — это первая версия игры

local function applyMigrations(profile)
	local data = profile.Data
	local version = data.DataVersion or 0
	for i = version + 1, #MIGRATIONS do
		local migration = MIGRATIONS[i]
		local ok, err = pcall(migration, data)
		if ok then
			data.DataVersion = i
		else
			-- Миграция упала — останавливаемся, данные остаются
			-- на прошлой совместимой версии. Это лучше, чем потерять профиль.
			warn(("[PlayerDataService] Ошибка миграции до версии %d: %s")
				:format(i, tostring(err)))
			break
		end
	end
end

-- ================================================================
-- ВНУТРЕННЕЕ СОСТОЯНИЕ МОДУЛЯ
-- ================================================================

local ProfileStore = nil -- объект хранилища ProfileService (создаётся в :Init)
local Profiles = {}      -- [Игрок] = профиль. Только активные, загруженные профили.

-- ================================================================
-- ВСПОМОГАТЕЛЬНЫЕ ПРОВЕРКИ (анти-чит первого рубежа)
-- ================================================================

-- Допустима ли сумма операции с валютой:
-- число, не NaN, не бесконечность, положительное, целое, в пределах потолка.
local function isValidAmount(amount)
	return type(amount) == "number"
		and amount == amount               -- отсекаем NaN (NaN ~= NaN)
		and amount ~= math.huge
		and amount > 0
		and amount <= MAX_CURRENCY
		and math.floor(amount) == amount  -- только целые числа
end

-- Корректен ли UId существа (строка GUID, которую выдали МЫ на сервере)
local function isValidUId(uid)
	return type(uid) == "string" and #uid >= 16 and #uid <= 40
end

-- ================================================================
-- ЖИЗНЕННЫЙ ЦИКЛ ПРОФИЛЯ (загрузка / выгрузка)
-- ================================================================

local function onPlayerAdded(player)
	-- Защита от двойной загрузки (событие PlayerAdded не должно
	-- срабатывать дважды, но дешёвая проверка экономит нам нервы)
	if Profiles[player] ~= nil then
		return
	end

	-- Ключ профиля привязан к UserId, а не к нику — игрок может
	-- менять ник, прогресс остаётся. "ForceLoad" забирает профиль,
	-- если он завис в мёртвой сессии (сервер упал и не отпустил).
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId, "ForceLoad")

	-- DataStore молчал слишком долго — просим перезайти
	if profile == nil then
		player:Kick("Не удалось загрузить данные. Пожалуйста, перезайдите в игру.")
		return
	end

	-- Игрок вышел, пока профиль грузился — сразу отпускаем профиль
	if not player:IsStillInGame() then
		profile:Release()
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: ассоциация профиля с аккаунтом
	profile:Reconcile()              -- доливаем недостающие поля шаблона
	applyMigrations(profile)         -- применяем миграции старых сейвов

	-- Если профиль силой заберёт ДРУГОЙ сервер (дублирующая сессия),
	-- этот сигнал сработает и мы выкинем игрока — так исключается
	-- дюп через двойной вход с двух устройств.
	profile:ListenToRelease(function()
		Profiles[player] = nil
		if player:IsStillInGame() then
			player:Kick("Ваш профиль открыт в другой сессии. Перезайдите в игру.")
		end
	end)

	Profiles[player] = profile

	-- Служебная статистика входа
	local stats = profile.Data.Stats
	if stats.FirstLogin == 0 then
		stats.FirstLogin = os.time()
	end
	stats.LastLogin = os.time()

	-- Атрибут-флаг: по нему клиент (в будущих шагах) поймёт,
	-- что данные загружены и можно показывать HUD.
	player:SetAttribute("DataLoaded", true)

	print(("[PlayerDataService] Профиль загружен: %s | Монеты: %d | Существ: %d")
		:format(player.Name, profile.Data.Coins, #profile.Data.Creatures))
end

local function onPlayerRemoving(player)
	local profile = Profiles[player]
	if profile ~= nil then
		Profiles[player] = nil
		profile:Release() -- отпускает профиль и сохраняет данные
	end
end

-- ================================================================
-- ПУБЛИЧНЫЙ API: инициализация
-- ================================================================

-- Init() вызывается из Main.server.lua ДО Start() всех сервисов.
-- Здесь создаём хранилище (без yield-вызовов).
function PlayerDataService:Init()
	ProfileStore = ProfileService.GetProfileStore(STORE_NAME, TEMPLATE)
end

-- Start() вызывается после Init() всех сервисов.
-- Здесь подписываемся на события (можно yield).
function PlayerDataService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player) -- каждый игрок грузится в своём потоке
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- На случай, если игроки зашли раньше, чем сервис стартовал
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	-- ВАЖНО: сохранение при выключении сервера (shutdown/обновление)
	-- ProfileService делает САМ через game:BindToClose — нам дублировать не нужно.
end

-- ================================================================
-- ПУБЛИЧНЫЙ API: доступ к данным (только для серверных сервисов)
-- ================================================================

-- Профиль загружен и активен?
function PlayerDataService:IsDataReady(player)
	return Profiles[player] ~= nil
end

-- Вернуть объект Profile (или nil). Нужен редко — для продвинутых сценариев.
function PlayerDataService:GetProfile(player)
	return Profiles[player]
end

-- Вернуть таблицу Data профиля (или nil).
-- Возвращается ЖИВАЯ ссылка: менять её поля напрямую можно только
-- внутри серверных сервисов. Клиенту эту таблицу не отправляем!
function PlayerDataService:GetData(player)
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end
	return profile.Data
end

-- Безопасное изменение данных другим сервисом:
--   PlayerDataService:ModifyData(player, function(data)
--       data.Stats.PlayTimeSeconds = data.Stats.PlayTimeSeconds + 60
--   end)
-- Колбэк не должен содержать yield-вызовов (task.wait и т.п.).
function PlayerDataService:ModifyData(player, callback)
	if type(callback) ~= "function" then
		return nil
	end
	local profile = Profiles[player]
	if profile == nil then
		return nil
	end
	return callback(profile.Data)
end

-- ================================================================
-- ПУБЛИЧНЫЙ API: валюты (Монеты / Эко-энергия / Rebirth-очки)
-- ================================================================

-- Сколько валюты у игрока (number или nil)
function PlayerDataService:GetCurrency(player, currency)
	if CURRENCIES[currency] ~= true then
		return nil
	end
	local data = self:GetData(player)
	if data == nil then
		return nil
	end
	return data[currency]
end

-- Начислить валюту. Возвращает: success [bool], newBalance [number], reason [string?]
function PlayerDataService:AddCurrency(player, currency, amount)
	if CURRENCIES[currency] ~= true then
		return false, nil, "unknown_currency"
	end
	if isValidAmount(amount) == false then
		return false, nil, "bad_amount" -- читерское/битое число — отказ
	end
	local data = self:GetData(player)
	if data == nil then
		return false, nil, "no_profile"
	end
	local newBalance = math.min(data[currency] + amount, MAX_CURRENCY)
	data[currency] = newBalance
	return true, newBalance
end

-- Списать валюту (АТОМАРНО: проверка и списание без yield между ними —
-- два одновременных запроса не «протратят» одни монеты дважды).
-- Возвращает: success [bool], newBalance [number?], reason [string?]
function PlayerDataService:SpendCurrency(player, currency, amount)
	if CURRENCIES[currency] ~= true then
		return false, nil, "unknown_currency"
	end
	if isValidAmount(amount) == false then
		return false, nil, "bad_amount"
	end
	local data = self:GetData(player)
	if data == nil then
		return false, nil, "no_profile"
	end
	if data[currency] < amount then
		return false, nil, "not_enough" -- не хватает средств
	end
	local newBalance = data[currency] - amount
	data[currency] = newBalance
	return true, newBalance
end

-- ================================================================
-- ПУБЛИЧНЫЙ API: инвентарь существ
-- ================================================================

-- Ёмкость инвентаря (базовые слоты + бонусы геймпассов в будущем)
function PlayerDataService:GetPetCapacity(player)
	local data = self:GetData(player)
	if data == nil then
		return 0
	end
	return data.BasePetSlots
end

-- Добавить существа в инвентарь. ВАЖНО: редкость и мутацию решает
-- СЕРВЕР (CreatureService в Шаге 3), а не клиент! Здесь только строгая валидация.
-- Возвращает: creature [table?] , reason [string?]
function PlayerDataService:AddCreature(player, speciesKey, rarity, mutation)
	-- Валидация входа
	if type(speciesKey) ~= "string" or #speciesKey == 0 or #speciesKey > 50 then
		return nil, "bad_species"
	end
	if rarity == nil then rarity = "Common" end
	if mutation == nil then mutation = "None" end
	if RARITIES[rarity] ~= true then
		return nil, "bad_rarity"
	end
	if MUTATIONS[mutation] ~= true then
		return nil, "bad_mutation"
	end
	-- Полная проверка, что такой вид существует, будет в Шаге 2
	-- (сверка с CreaturesConfig) — сейчас проверяем длину строки.

	local data = self:GetData(player)
	if data == nil then
		return nil, "no_profile"
	end

	-- Проверка свободного места
	if #data.Creatures >= self:GetPetCapacity(player) then
		return nil, "inventory_full"
	end

	-- Создание записи. UId генерирует ТОЛЬКО сервер — это гарантия
	-- уникальности и основа анти-дюпа при трейде (Шаг 6).
	local creature = {
		UId = HttpService:GenerateGUID(false),
		Species = speciesKey,
		Rarity = rarity,
		Mutation = mutation,
		Level = 1,
		HatchedAt = os.time(),
		Locked = false, -- true = игрок запретил продажу/трейд этого существа
	}
	table.insert(data.Creatures, creature)
	return creature
end

-- Найти существо по UId (живая ссылка или nil)
function PlayerDataService:GetCreatureByUId(player, uid)
	if isValidUId(uid) == false then
		return nil
	end
	local data = self:GetData(player)
	if data == nil then
		return nil
	end
	for _, creature in ipairs(data.Creatures) do
		if creature.UId == uid then
			return creature
		end
	end
	return nil
end

-- Убрать существо из инвентаря (продажа, трейд, жертва ритуала).
-- Заблокированных (Locked) существ убрать нельзя.
-- Возвращает: creature [table?], reason [string?]
function PlayerDataService:RemoveCreature(player, uid)
	if isValidUId(uid) == false then
		return nil, "bad_uid"
	end
	local data = self:GetData(player)
	if data == nil then
		return nil, "no_profile"
	end
	for index, creature in ipairs(data.Creatures) do
		if creature.UId == uid then
			if creature.Locked == true then
				return nil, "locked" -- игрок сам запретил удаление
			end
			table.remove(data.Creatures, index)
			return creature
		end
	end
	return nil, "not_found"
end

-- Блокировка/разблокировка существа от продажи и трейда
function PlayerDataService:SetCreatureLocked(player, uid, locked)
	local creature = self:GetCreatureByUId(player, uid)
	if creature == nil then
		return false, "not_found"
	end
	creature.Locked = (locked == true)
	return true
end

return PlayerDataService
