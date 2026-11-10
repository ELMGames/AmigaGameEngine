;==============================================================================
; AMIGA GAME ENGINE
; entity_variables.i  -  Entity pool fields for the Variables block
;==============================================================================
;
; Included by a game's variables.asm, after engine_variables.i and on the same
; rsreset chain, when the game includes engine/gameplay/entities.asm. The
; struct sizes come from entity_struct.i; the pool sizes are the game's
; (MAX_ACTIVE_ENEMIES, MAX_ACTIVE_FRIENDS, MAX_ACTIVE_PICKUPS).
;==============================================================================

ActiveEnemyCount:     rs.w    1               ; number of active enemies (0..MAX_ACTIVE_ENEMIES)
ActiveEnemies:        rs.b    Enemy_Sizeof*MAX_ACTIVE_ENEMIES ; runtime enemy instances array
EnemyDrawOrder:       rs.l    MAX_ACTIVE_ENEMIES ; enemy pointers sorted by Enemy_Y (top first)
EnemyDrawCount:       rs.w    1               ; entries in EnemyDrawOrder (tracks ActiveEnemyCount)
ActiveFriendCount:    rs.w    1               ; number of active friends (0..MAX_ACTIVE_FRIENDS)
ActiveFriends:        rs.b    Friend_Sizeof*MAX_ACTIVE_FRIENDS ; runtime friend instances array
FriendsCollectedCount: rs.w   1               ; number of collected friends
ActivePickupCount:    rs.w    1               ; number of active pickups (0..MAX_ACTIVE_PICKUPS)
ActivePickups:        rs.b    Pickup_Sizeof*MAX_ACTIVE_PICKUPS ; runtime pickups array
