extends Resource
## A complete street lighting state, blended by StreetWeather.
@export var title: String
@export var top_color: Color
@export var horizon_color: Color
@export var cloud_color: Color = Color.WHITE
@export var cloud_cover: float = 0.18
@export var sun_color: Color = Color(1, 0.94, 0.79)
@export var sun_energy: float = 1.5
@export var sun_rotation: Vector3 = Vector3(-38, -32, 0)
@export var ambient_color: Color = Color(0.76, 0.88, 0.98)
@export var ambient_energy: float = 0.7
@export var fog_color: Color = Color(0.77, 0.86, 0.94)
@export var fog_density: float = 0.0015
@export var fog_height: float = 0.0
@export var fog_height_density: float = 0.0
@export var rain: float = 0.0
