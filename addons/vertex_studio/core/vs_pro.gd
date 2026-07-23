@tool
extends RefCounted
class_name VSPro

## Edition gate for the free vs pro versions. Single source of truth for the PRO feature list.
##

const IS_PRO := false
const ALERT := "This feature is available in VERTEX STUDIO PRO. Upgrade to unlock."
const STORE_URL := "https://splitpainter.itch.io/vertex-studio"

enum Feature {
	SPLIT_VERTS,
	SELECT_LASSO,
	SELECT_RECTANGLE,
	SELECT_ELLIPSE,
	SELECT_POINT_DRAG,
	SELECT_LINKED,
	INVERT_SELECTION,
	PAINT_PRECISION,
	PAINT_NORMALS,
	VERTEX_GROUPS,
	SNAPSHOTS,
	REPLACE_COLORS,
	SINGLE_CHANNEL,
	FALLOFF,
	RESYNC_UVS,
}


static func locked(_feature: int) -> bool:
	return not IS_PRO
