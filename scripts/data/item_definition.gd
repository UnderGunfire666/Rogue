@tool
class_name ItemDefinition
extends Resource

enum Recipient { PLAYER, ENEMY }
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var recipient: Recipient = Recipient.PLAYER
@export_range(1, 5) var rarity: int = 1
