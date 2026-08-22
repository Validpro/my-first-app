# 🌊 ЭкоРиф: Симулятор Спасения Океана

Исходники игры для Roblox (язык **Luau**). Репозиторий повторяет структуру
древа объектов Roblox Studio: путь к файлу здесь = путь в Explorer Studio.

---

## 📁 Карта проекта (полная архитектура)

Ниже — итоговая структура. Объекты, помеченные *(будущее)*, создаём по мере шагов.
**Жирным** — то, что существует уже сейчас (Шаг 1).

```
ReplicatedStorage                    (встроенный сервис Roblox)
├── Packages                         (Folder) — сторонние библиотеки для клиента (будущее)
├── Shared                           (Folder) — ОБЩИЕ модули (видят и сервер, и клиент)
│   ├── Configs                      (Folder) — игровые таблицы данных
│   │   ├── CreaturesConfig          (ModuleScript, будущее) — 20 существ MVP
│   │   ├── ZonesConfig              (ModuleScript, будущее) — зоны, пороги очистки 25/50/75/100%
│   │   ├── UpgradesConfig           (ModuleScript, будущее) — 5 апгрейдов и цены
│   │   └── GameConstants            (ModuleScript, будущее) — глобальные константы
│   ├── Modules                      (Folder) — утилиты (RNG-хелперы и т.п., будущее)
│   └── Remotes                      (Folder) — RemoteEvent/RemoteFunction,
│                                           создаёт СЕРВЕР программно (будущее)
└── Assets                           (Folder) — модели, атласы текстур, звуки (ваш контент)

ServerScriptService                  (встроенный сервис Roblox)
├── Packages                         (Folder)
│   └── ProfileService               (ModuleScript) ✅ — официальная библиотека сохранений
│                                            github.com/MadStudioRoblox/ProfileService (MIT)
└── Server                           (Folder)
    ├── Main                         (Script) ✅ — точка входа сервера
    └── Services                     (Folder)
        ├── PlayerDataService        (ModuleScript) ✅ — данные игроков (валюты, инвентарь)
        ├── TrashService             (ModuleScript, будущее) — спавн/сбор/переработка мусора
        ├── CreatureService          (ModuleScript, будущее) — существа, яйца, гнёзда, RNG
        ├── ZoneService              (ModuleScript, будущее) — прогресс биома «До/После»
        ├── RebirthService           (ModuleScript, будущее) — ребёрн
        ├── TradeService             (ModuleScript, будущее) — торговля (2 этапа подтверждения)
        └── AntiCheatService         (ModuleScript, будущее) — анти-чит / анти-дюп

StarterPlayer → StarterPlayerScripts (встроенные сервисы Roblox)
└── Client                           (Folder, будущее)
    ├── Main                         (LocalScript) — точка входа клиента
    └── Controllers                  (Folder) — HUD, вакуум-луч, инвентарь UI
```

### Соответствие файлов репозитория объектам Studio

| Файл в репозитории | Объект в Studio | Класс |
|---|---|---|
| `ServerScriptService/Server/Packages/ProfileService.lua` | `ServerScriptService → Server → Packages → ProfileService` | ModuleScript |
| `ServerScriptService/Server/Main.server.lua` | `ServerScriptService → Server → Main` | Script |
| `ServerScriptService/Server/Services/PlayerDataService.lua` | `ServerScriptService → Server → Services → PlayerDataService` | ModuleScript |

Суффикс `.server.lua` в имени файла = обычный серверный **Script**,
`.client.lua` = **LocalScript**, просто `.lua` = **ModuleScript**.

---

## 🛠 Установка Шага 1 в Roblox Studio (5–10 минут)

1. **Создайте папки.** В окне Explorer наведите курсор на `ServerScriptService`,
   нажмите **+** → выберите **Folder** → назовите `Server` (переименование — F2).
   Внутри `Server` создайте ещё две папки: `Packages` и `Services`.
2. **ProfileService.** В папке `Packages`: **+** → **ModuleScript** → назовите
   `ProfileService`. Откройте файл `ProfileService.lua` из этого репозитория,
   скопируйте ВСЁ содержимое и вставьте в модуль (старый код-заглушку удалить).
3. **Main.** В папке `Server`: **+** → **Script** (не LocalScript!) → назовите
   `Main`. Вставьте содержимое `Main.server.lua`.
4. **PlayerDataService.** В папке `Services`: **+** → **ModuleScript** → назовите
   `PlayerDataService`. Вставьте содержимое `PlayerDataService.lua`.
5. **Включите сохранения.** Меню **File → Publish to Roblox As...** (один раз),
   затем **Home → Game Settings → Security → Enable Studio Access to API Services = ON**.

> ⚠️ Если API-доступ не включён, игра всё равно запустится: ProfileService
> перейдёт в тестовый режим и напишет в Output:
> `"[ProfileService]: Roblox API services unavailable - data will not be saved"`.
> Данные будут жить только до конца теста.

---

## ✅ Как проверить, что всё работает

1. Откройте окно **View → Output**.
2. Нажмите **Play (F5)**.
3. В Output должно появиться:
   ```
   [Main] Init: PlayerDataService
   [Main] Start: PlayerDataService
   [ЭкоРиф] Сервер запущен. Приятной очистки океана! 🌊
   [PlayerDataService] Профиль загружен: <ВашНик> | Монеты: 0 | Существ: 0
   ```
4. **Тест API модуля** (по желанию): во время Play нажмите Stop, снова Play,
   вверху окна Studio переключитесь на **Server** (кнопка Client/Server), и в
   **Command Bar** (View → Command Bar) выполните:
   ```lua
   local PDS = require(game:GetService("ServerScriptService").Server.Services.PlayerDataService)
   local plr = game:GetService("Players"):GetPlayers()[1]
   print(PDS:AddCurrency(plr, "Coins", 500))          --> true  500
   print(PDS:AddCreature(plr, "Clownfish", "Rare", "Shiny"))  --> таблица существа
   print(PDS:GetData(plr).Coins, #PDS:GetData(plr).Creatures) --> 500  1
   ```

---

## 🗺 Дорожная карта MVP

| Шаг | Что делаем | Статус |
|---|---|---|
| 1 | ProfileService + PlayerDataService + Main | ✅ Готово |
| 2 | GameConstants, CreaturesConfig (20 существ), UpgradesConfig (5 апгрейдов) | ⬜ |
| 3 | Зона «Мелководье»: мусор, сбор, переработка в Эко-энергию, % очистки | ⬜ |
| 4 | Гнёзда, яйца (RNG на сервере), инвентарь UI, риф пассивного дохода | ⬜ |
| 5 | Rebirth + сброс зоны с новым паттерном мусора | ⬜ |
| 6 | Клиент: HUD, вакуум-луч, визуальные стадии «До/После» (25/50/75/100%) | ⬜ |
| 7 | Trade (2 этапа), кланы, монетизация (без P2W), анти-чит | ⬜ |

---

## 🔒 Железные правила безопасности проекта

1. **Сервер — источник истины.** RNG, лут, валюты, трейд — только на сервере.
2. **Клиенту не доверяем ничего.** Любое число от клиента проходит валидацию
   (`isValidAmount`: тип, NaN, ±∞, целое, потолок).
3. **UId существ выдаёт только сервер** (GUID) — анти-дюп для трейда.
4. **Сессионные локи ProfileService** защищают от дюпа через двойной вход.
5. **Профиль привязан к UserId**, а не к нику.
6. Никогда не кладём логику данных в ReplicatedStorage — клиент не должен
   даже видеть код, который пишет в профиль.
