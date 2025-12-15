# sd-waypoints

> A stylish 3D waypoint marker for FiveM that displays distance to your map waypoint with smooth animations and multiple visual styles.

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/c5a5c17e-ec61-4ce7-be65-207d0e3fdcd0" />

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/0ca6b325-cac3-4924-be3f-743009af0b04" />

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/748b5c7f-3317-4780-9b50-256ab81dad88" />



![GitHub release](https://img.shields.io/github/v/release/Samuels-Development/sd-waypoints?label=Release&logo=github)
[![Discord](https://img.shields.io/discord/842045164951437383?label=Discord&logo=discord&logoColor=white)](https://discord.gg/FzPehMQaBQ)

## 📋 Dependencies

- [ox_lib](https://github.com/overextended/ox_lib)

## 🎯 Features

- **3D World Marker** - Displays a floating marker above your waypoint location in the game world
- **Live Distance** - Real-time distance updates as you travel toward your destination
- **Multiple Styles** - Choose from classic, modern, or elegant visual designs
- **Smooth Animations** - Height adjusts dynamically based on distance with smooth lerp transitions
- **Unit System** - Supports both metric (m/km) and imperial (ft/mi) measurements
- **Customizable Color** - Set your preferred marker color via hex code

---

## ⚠️ Performance Note

While efforts have been made to optimize this resource, it does run at a higher baseline than typical scripts due to the DUI (Dynamic UI) rendering required for the marker display. 

**Expected Performance:**
- ~0.00ms when no waypoint is set
- ~0.01-0.02ms when waypoint is set but you're not actively looking at it
- ~0.05-0.07ms when waypoint is active and driving toward it

The render thread must run every frame to display the sprite, and the DUI browser engine adds inherent overhead. This is a trade-off for the visual flexibility that DUI provides.

---

## 📦 Installation

1. [Download the latest release](https://github.com/Samuels-Development/sd-waypoints/releases/latest)
2. Ensure `ox_lib` is started before `sd-waypoints`
3. Add `sd-waypoints` to your resources folder
4. Add `ensure sd-waypoints` to your server.cfg

---

## 🛠️ Configuration

All settings are defined in `config.lua`:

```lua
return {
    -- Locale for translations (e.g., 'en', 'de')
    Locale = 'en',

    -- Waypoint marker style
    -- Options: 'classic', 'modern', 'elegant'
    Style = 'classic',

    -- The color of the waypoint marker (hex color code)
    Color = '#22C55E',

    -- Unit system for distance display
    -- true = Metric (meters and kilometers)
    -- false = Imperial (feet and miles)
    UseMetric = true,
}
```

### Style Options

| Style | Description |
|-------|-------------|
| `classic` | Large distance display with divider and label |
| `modern` | Clean badge design with colored label bar |
| `elegant` | Decorative frame with corner accents and diamond separator |

---

## 🎨 Customization

### Changing the Color

Set any valid hex color code:

```lua
Color = '#22C55E',  -- Green (default)
Color = '#3B82F6',  -- Blue
Color = '#EF4444',  -- Red
Color = '#F59E0B',  -- Amber
```

### Switching Unit Systems

```lua
UseMetric = true,   -- Shows: 150 M, 1.2 KM
UseMetric = false,  -- Shows: 492 FT, 0.7 MI
```

---

## 🌐 Localization

Translation files are located in the `locales/` folder. The marker displays the localized "WAYPOINT" label based on your configured locale.

To add a new language, create a new file in `locales/` (e.g., `fr.json`) following the existing format.

---
