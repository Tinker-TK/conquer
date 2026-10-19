# Demo Scene Guide

The VFX Library includes an interactive demo scene that showcases all available particle effects and shader effects with a visual testing interface.

## 🎮 Running the Demo

### Quick Start
1. Open `assets/effect/godot_vfx_library/demo/vfx_demo.tscn` in Godot
2. Press **F6** (Play Scene) or click the scene play button
3. Select effects from the list and right-click to spawn them

### Alternative Access
- Set as main scene: Project Settings → Run → Main Scene → `res://assets/effect/godot_vfx_library/demo/vfx_demo.tscn`
- Run from project.godot if already configured

## 🎯 How to Use

### Testing Particle Effects

1. **Select an Effect**
   - Browse the left panel "特效列表" (Effect List)
   - Click on any effect to select it
   - Effects are organized by category with emoji icons

2. **Spawn Effects**
   - **Right-click** anywhere in the scene to spawn the selected effect
   - The effect will appear at your mouse cursor position
   - You can spawn multiple effects at different positions

3. **Clear Effects**
   - Click the "清空所有特效" (Clear All Effects) button to remove all spawned effects
   - This helps keep the scene clean and test performance

### Testing Shader Effects

1. **Select a Shader**
   - Browse the right panel "Shader列表" (Shader List)
   - Click on any shader to select it
   - 17 shader effects are available

2. **Apply Shader**
   - Click "应用Shader" (Apply Shader) to apply the selected shader to the test sprite
   - Watch the animated shader effects in real-time
   - Each shader has unique animation parameters

3. **Remove Shader**
   - Click "移除Shader" (Remove Shader) to clear the shader from the test sprite

### Controls

- **Right Mouse Button** - Spawn selected effect at cursor position
- **ESC** - Exit demo

## 📋 Available Effects

### Particle Effects (35+)

**Environmental Effects** (🌲 Continuous)
- 🔥 Torch Fire - Flickering torch flame
- 🌟 Fireflies - Ambient glowing bugs
- 🍂 Falling Leaves - Autumn leaves drifting
- ☁️ Steam - Rising steam vapor
- ✨ Sparks - Electric/fire sparks
- 🔮 Magic Aura - Mystical glow around objects
- ☠️ Poison Cloud - Toxic gas cloud

**Weather Effects** (🌦️ Continuous)
- 🌧️ Rain - Rainfall effect
- ❄️ Snow - Snowfall effect
- 💦 Waterfall Mist - Water vapor
- 🌫️ Ash Particles - Floating ash
- 🔥 Campfire Smoke - Smoke rising from fire
- 🕯️ Candle Flame - Small candle fire

**Combat Particles** (⚔️ Colored)
- 🔴 Fire Particle - Red/orange flames
- 🔵 Ice Particle - Blue/white frost
- 🟢 Poison Particle - Green toxic
- 🟡 Lightning Particle - Yellow electric
- 🟣 Shadow Particle - Dark purple

**Combat Effects** (💥 One-shot)
- 🩸 Blood Splash - Impact blood splatter
- 💥 Energy Burst - Magical explosion
- 💚 Heal Effect - Healing particles
- 🛡️ Shield Break - Shield destruction
- 🌀 Combo Ring - Combo indicator ring
- 💨 Jump Dust - Ground dust from jump

**Skill Effects** (🔮 Special)
- 👻 Dash Trail - Movement trail (continuous)
- ⚡ Wall Slide Spark - Wall friction sparks (continuous)
- 🌀 Portal Vortex - Teleport portal (continuous)
- ⚡ Lightning Chain - Electric discharge (one-shot)
- ❄️ Ice Frost - Freezing effect (one-shot)
- 🔥 Fireball Trail - Projectile trail (continuous)
- 🔯 Summon Circle - Summoning ritual (continuous)
- 🪵 Wood Debris - Breaking wood (one-shot)
- 💧 Water Splash - Water impact (one-shot)
- 💨 Dust Cloud - Dust explosion (one-shot)

### Shader Effects (17+)

**Status Effects**
- 🔥 Burning - Fire damage visual
- ❄️ Frozen - Ice freeze effect
- ☠️ Poison - Poisoned state
- 🗿 Petrify - Turned to stone
- 👻 Invisibility - Transparency/distortion

**Visual Transformations**
- 💥 Dissolve - Disintegration effect
- ⚡ Blink - Rapid flashing
- 🌊 Water Surface - Water shader
- 🔆 Flash White - Damage flash
- 🎨 Color Change - Color tinting

**Screen Effects**
- 🌫️ Fog - Fog overlay
- 🔥 Heat Distortion - Heat wave effect
- 🌀 Radial Blur - Motion blur from center
- 🎭 Grayscale - Black and white
- 🌈 Chromatic Aberration - RGB split
- 🔲 Vignette - Edge darkening
- ✨ Outline Glow - Glowing outline

## 🧪 Testing Features

The demo provides comprehensive testing capabilities:

- **Real-time Spawning**: Click to spawn effects instantly
- **Multiple Effects**: Spawn many effects to test combinations
- **Shader Animation**: All shaders have animated parameters
- **Easy Cleanup**: One-click to clear all effects
- **Visual Feedback**: See effects exactly as they'll appear in-game

## 📊 Demo Scene Structure

```
vfx_demo.tscn
├── UI/
│   ├── Panel/                    # Effect list panel
│   │   ├── EffectList           # Scrollable effect selection
│   │   └── ClearButton          # Clear all effects
│   └── ShaderPanel/             # Shader test panel
│       ├── ShaderList           # Scrollable shader selection
│       ├── ApplyShaderButton    # Apply selected shader
│       └── RemoveShaderButton   # Remove shader
├── Camera2D                     # Scene camera
├── Background                   # Visual backdrop  
├── ShaderTestSprite            # Sprite for shader testing
└── (Dynamic Effects)           # Effects spawn here
```

### Scene Components

The demo uses a list-based UI for easy effect browsing:

- **Effect List Panel**: Shows all 35+ particle effects organized by category
- **Shader List Panel**: Shows all 17+ shader effects
- **Test Sprite**: Centered sprite for shader visualization
- **Dynamic Spawning**: Effects spawn at mouse cursor position when right-clicking

## 🎯 Use Cases

### For Developers

**Integration Testing**

```gdscript
# Test VFX integration in your game
func test_combat_effects():
    VFX.spawn_blood_splash(enemy.global_position)
    VFX.screen_shake(10.0, 0.2)
    VFX.freeze_frame(0.1)
```

**Performance Validation**

- Test effect combinations that might occur in gameplay
- Validate frame rate with multiple simultaneous effects
- Check memory usage patterns with the clear button

**Visual Design**

- Preview effects with your game's art style
- Test color combinations and intensities
- Evaluate effect timing and duration
- Compare shader effects side-by-side

### For Artists

**Effect Customization**

1. Use demo to identify effects to modify
2. Open corresponding `.tscn` files in `addons/vfx_library/effects/`
3. Adjust particle properties visually
4. Test changes using the demo scene

**Shader Testing**

1. Browse shader effects in the demo
2. Apply shaders to see animated previews
3. Modify shader files in `addons/vfx_library/shaders/`
4. Test parameter adjustments in real-time

**Color Palette Integration**
- Test how effects look with your game's colors
- Modify effect colors in the scene files
- Use the demo to compare original vs. customized effects

### For Game Designers

**Gameplay Integration**
- Experience effects in context
- Evaluate impact timing and visual feedback
- Test effect combinations for different game scenarios

**Balancing Feedback**
- Assess if effects are too subtle or overwhelming
- Test readability during intense action sequences
- Validate effect duration for game pacing

## 🔧 Customizing the Demo

### Adding New Effects

To add your custom effects to the demo:

1. **Add Effect Reference**

```gdscript
# In vfx_demo.gd, add to effects_data array
{"name": "🆕 Your Effect", "type": "vfx", "func": "your_function_name"}
```

2. **Add Spawn Function**

```gdscript
func spawn_vfx_effect(effect: Dictionary, pos: Vector2):
    var vfx = get_node("/root/VFX")
    var func_name = effect["func"]
    if vfx.has_method(func_name):
        vfx.call(func_name, pos)
```

### Modifying UI

**Panel Positions**

```gdscript
# Adjust panel positions in the scene
$UI/Panel.position = Vector2(new_x, new_y)
$UI/ShaderPanel.position = Vector2(new_x, new_y)
```

**List Appearance**

- Edit the ItemList nodes in the scene
- Adjust colors, fonts, and sizes
- Modify ScrollContainer for different layouts

### Adding Shader Tests

To add custom shaders to the demo:

1. **Add to Shader List**

```gdscript
# In setup_shaders_list()
shaders_data.append({
    "name": "🆕 Your Shader",
    "path": "res://path/to/your_shader.gdshader"
})
```

2. **Add Shader Parameters**

```gdscript
# In _on_apply_shader_pressed(), add your shader setup
elif "Your Shader" in shader_name:
    shader_mat.set_shader_parameter("your_param", value)
```

3. **Optional: Add Animation**

```gdscript
# In _process(delta), add animation logic
elif "Your Shader" in shader_name:
    var animated_value = sin(shader_animation_time * speed) * amplitude
    shader_mat.set_shader_parameter("param_name", animated_value)
```

## 📝 Demo Script Reference

### Key Functions

**`spawn_current_effect(pos: Vector2)`**
- Spawns the selected effect at the specified position
- Automatically routes to correct spawn function based on effect type
- Handles cleanup for one-shot effects

**`spawn_env_effect(effect: Dictionary, pos: Vector2)`**
- Handles persistent environmental effects
- Creates holder nodes for effects that need a parent
- Manages effect lifecycle

**`spawn_vfx_effect(effect: Dictionary, pos: Vector2)`**
- Handles VFX system one-shot effects
- Calls VFX singleton methods
- Auto-cleanup after effect completion

**`setup_effects_list()`**
- Initializes the effect list with all 35+ effects
- Organizes effects by category with emoji icons
- Populates the UI ItemList

**`setup_shaders_list()`**
- Initializes shader list with all 17+ shaders
- Loads shader paths
- Prepares for shader application

**`_on_apply_shader_pressed()`**
- Loads selected shader
- Creates ShaderMaterial
- Applies to test sprite with animated parameters

### Effect Types

The demo handles 5 effect types:

- **`env`** - Environmental effects (continuous, needs holder)
- **`env_oneshot`** - Environmental one-shot (auto-cleanup)
- **`env_continuous`** - Environmental continuous (needs holder)
- **`vfx`** - VFX one-shot effects (auto-cleanup)
- **`vfx_continuous`** - VFX continuous (needs holder)
- **`combat`** - Colored combat particles (via VFX.spawn_particles)

## 🚀 Performance Tips

### Optimization Testing

1. **Stress Test**: Spawn many effects simultaneously by rapidly right-clicking
2. **Memory Test**: Use clear button to verify proper cleanup
3. **Shader Performance**: Test multiple shaders on different sprites

### Frame Rate Targets

- **Desktop**: 60 FPS with 10-20 simultaneous effects
- **Mobile**: 30-60 FPS with 5-10 simultaneous effects  
- **Web**: 30-45 FPS with 3-5 simultaneous effects

### Optimization Guidelines

- Limit particle counts (50-200 per effect)
- Use auto-cleanup for one-shot effects
- Monitor spawned_effects array size
- Clear unused effects regularly
- Test shader combinations for performance impact

---

The demo scene is your playground for exploring the VFX Library's capabilities. Browse effects, test shaders, and integrate them into your game with confidence! 🎮✨
