--[[
	================================================================
	ЭКОРИФ: Симулятор Спасения Океана
	================================================================
	Файл:         Main
	Тип объекта:  Script (обычный серверный скрипт, НЕ LocalScript!)
	Расположение: ServerScriptService → Server → Main

	НАЗНАЧЕНИЕ:
		Точка входа сервера. Подключает все серверные сервисы
		в правильном порядке:

		  1) У всех сервисов вызывается :Init()  — создание объектов,
		     никаких ожиданий (yield) и подписок на события.
		  2) У всех сервисов вызывается :Start() — подписка на события
		     игроков, запуск циклов. Стартуют параллельно, чтобы
		     один медленный сервис не тормозил остальные.

		Это профессиональный паттерн: он исключает ошибки вида
		«сервис Б загрузился раньше, чем сервис А создал данные».

	Версия: 1.0 (Шаг 1 дорожной карты MVP)
	================================================================
]]

local ServerFolder = script.Parent                 -- ServerScriptService → Server
local ServicesFolder = ServerFolder:WaitForChild("Services")

-- Порядок загрузки сервисов. По мере развития проекта добавляем сюда
-- имена новых ModuleScript'ов (файл должен лежать в папке Services).
local SERVICE_ORDER = {
	"PlayerDataService", -- Шаг 1: данные игроков (ВСЕГДА первый!)
	-- "ZonesConfig",     -- будущее
	-- "TrashService",    -- Шаг 3: мусор и переработка
	-- "CreatureService", -- Шаг 3-4: существа, яйца, гнёзда
	-- "ZoneService",     -- Шаг 3: прогресс биома «До/После»
	-- "RebirthService",  -- Шаг 5: ребёрн
	-- "TradeService",    -- Шаг 6: торговля
	-- "AntiCheatService",-- Шаг 7: анти-чит
}

-- ЭТАП 1: Init — подключаем и инициализируем все сервисы по порядку
local services = {}
for _, serviceName in ipairs(SERVICE_ORDER) do
	local module = ServicesFolder:WaitForChild(serviceName)
	local service = require(module)
	services[serviceName] = service
	if type(service.Init) == "function" then
		service:Init()
	end
	print(("[Main] Init: %s"):format(serviceName))
end

-- ЭТАП 2: Start — запускаем все сервисы (параллельно)
for _, serviceName in ipairs(SERVICE_ORDER) do
	local service = services[serviceName]
	if type(service.Start) == "function" then
		task.spawn(function()
			service:Start()
		end)
		print(("[Main] Start: %s"):format(serviceName))
	end
end

print("[ЭкоРиф] Сервер запущен. Приятной очистки океана! 🌊")
