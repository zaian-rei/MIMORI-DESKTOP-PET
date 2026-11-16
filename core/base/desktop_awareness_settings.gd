extends Resource
class_name DesktopAwarenessSettings

## Data-driven tuning for DesktopAwarenessComponent - the pet's view of its
## environment. All of these used to be hardcoded constants scattered across
## components; they now live here so future settings screens can retune the
## pet's environmental sense with zero engine changes (same pattern as
## MovementSettings and FollowCursorSettings).

## How often the component re-scans the desktop for changes (monitor swaps,
## resolution/arrangement changes, window moves). Pure query methods still
## compute fresh values on every call; this only gates signal detection and
## cached multi-monitor info. Seconds.
@export var refresh_interval: float = 0.5

## Distance (px) within which the cursor counts as "in interaction range".
## Drives is_cursor_in_interaction_range() and the cursor_entered/exited
## signals.
@export var cursor_interaction_radius: float = 60.0

## Distance (px) from a screen edge at which the pet is considered "near"
## that edge. Drives is_near_left/right/any_edge().
@export var edge_padding: float = 24.0

## Inset (px) on each horizontal side of the current monitor that defines
## the pet's safe walking area - the x-range it may roam without risk.
@export var safe_walking_margin: float = 32.0

## Gap (px) between the bottom of the usable screen area and the floor the
## pet stands on. 0.0 defers to PetDefinition.floor_offset (the existing
## source of truth), so the default configuration changes nothing about how
## the pet currently lands.
@export var floor_offset: float = 0.0
