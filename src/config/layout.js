// Single source of truth for every coordinate in the level.
// Units: meters. Y is up. The main room floor is y = 0.
// Model convention: an unrotated model's FRONT faces +Z.
//   rotY = 0      -> front faces +Z (south)
//   rotY = PI     -> front faces -Z (north)
//   rotY = -PI/2  -> front faces -X (west)
//   rotY = +PI/2  -> front faces +X (east)
// North = -Z, South = +Z, West = -X, East = +X.

export const PI = Math.PI;

export const ROOM = {
  minX: -3.5, maxX: 3.5,       // interior faces of west / east walls
  minZ: -2.75, maxZ: 2.75,     // interior faces of north / south walls
  floorY: 0,
  ceilingY: 2.5,
  wallThickness: 0.2,
};

// Upper floor (ground floor of the house). Only the landing + a short hallway behind the door exist.
export const UPPER = {
  floorY: 2.75,
  ceilingY: 5.2,
};

// Straight stair run against the west wall, climbing toward the north.
export const STAIRS = {
  minX: -3.5, maxX: -2.55,     // stair width 0.95
  bottomZ: 1.6,                // south edge of the first riser (floor level south of this)
  risers: 14,
  riserHeight: 2.75 / 14,      // 0.19643
  treadDepth: 0.26,
  // topZ = bottomZ - 13 * treadDepth = -1.78 ; landing occupies z in [ROOM.minZ, topZ]
  get topZ() { return this.bottomZ - (this.risers - 1) * this.treadDepth; },
  // The room ceiling is open above the stairs for z < ceilingOpeningMaxZ (stairwell up to UPPER.ceilingY).
  ceilingOpeningMaxZ: 1.15,
  // Knee wall + railing line on the east side of the stairs (blocks walking in from the side).
  sideWallX: -2.55,
  sideWallThickness: 0.1,
};

// Height of the stair surface at (x,z) — floor of each tread. Returns null when not over the stairs footprint.
export function stairHeightAt(x, z) {
  if (x < STAIRS.minX || x > STAIRS.maxX) return null;
  if (z > STAIRS.bottomZ) return null;
  if (z <= STAIRS.topZ) return UPPER.floorY; // landing
  const k = Math.ceil((STAIRS.bottomZ - z) / STAIRS.treadDepth); // 1..13
  return Math.min(k, STAIRS.risers) * STAIRS.riserHeight;
}

// Door at the top of the stairs (north wall of the landing). Hinge on the WEST side, swings into the stairwell (toward +Z).
export const UPSTAIRS_DOOR = {
  centerX: -3.025, z: -2.75, width: 0.85, height: 2.03, bottomY: 2.75, thickness: 0.045,
  hingeX: -3.45,           // hinge line x (west edge)
  openAngle: -1.6,         // rotation.y of the door pivot when fully open (swings toward +Z)
};
// Short lit hallway behind the upstairs door (only visible when the door opens; reaching it = win).
export const UPPER_HALL = { minX: -3.6, maxX: -2.45, minZ: -4.4, maxZ: -2.75 };

// Closet under the stairs (hiding spot). Enclosed by the knee wall at x = STAIRS.sideWallX.
export const CLOSET = {
  minX: -3.45, maxX: -2.62, minZ: -2.7, maxZ: -0.35,
  // Louvered door in the knee wall, facing east. Hinge at the north edge.
  door: { x: -2.55, centerZ: -2.05, width: 0.62, height: 1.9, hingeZ: -2.36, openAngle: 1.5 },
  // Where the camera sits while hidden (looking east through the louvers).
  hidePos: { x: -3.05, y: 1.35, z: -2.05 }, hideYaw: -PI / 2, // yaw: camera looks toward +X
  exitPos: { x: -2.05, z: -2.05 },
};

// Laundry nook ("buanderie") behind the north wall, through an open doorway (no door).
export const ALCOVE = {
  minX: 0.2, maxX: 3.5, minZ: -4.6, maxZ: -2.75,
  doorway: { minX: 0.9, maxX: 1.8, height: 2.05 },
};

// Small high basement window in the south wall (barred, too small to escape).
export const WINDOW = { minX: 1.95, maxX: 2.95, minY: 1.8, maxY: 2.3, z: 2.75 };

// Ceiling fan + main light.
export const FAN = { x: 0.25, z: 0.35 }; // model hangs from y = ROOM.ceilingY (model origin is the ceiling mount)

// Furniture / prop placement. `pos` is the model origin position. `scale` defaults to 1.
// Footprints for colliders are computed from the model bounding box after rotation.
export const PROPS = {
  sofa:          { model: 'sofa_03', pos: [0.25, 0, 2.27], rotY: PI },
  pillows:       { model: 'throw_pillows_01', pos: [0.25, 0.47, 2.3], rotY: PI }, // tune y to sit on seat
  coffeeTable:   { model: 'small_wooden_table_01', pos: [0.25, 0, 0.95], rotY: 0 },
  endTable:      { model: 'painted_wooden_nightstand', pos: [-1.5, 0, 2.42], rotY: PI }, // drawer faces north; battery #1 inside
  dresser:       { model: 'GothicCommode_01', pos: [-0.55, 0, -2.44], rotY: 0 },        // 3 drawers; flashlight in TOP drawer (door01)
  tv:            { model: 'television_02', pos: [-0.55, 1.212, -2.5], rotY: 0 },
  photoFrame:    { model: 'standing_picture_frame_01', pos: [-0.05, 1.212, -2.45], rotY: -0.3 },
  grandfather:   { model: 'vintage_grandfather_clock_01', pos: [2.95, 0, -2.52], rotY: 0 },
  shelves:       { model: 'painted_wooden_shelves', pos: [2.15, 0, -2.75], rotY: 0 },   // origin is at its back face
  books:         { model: 'book_encyclopedia_set_01', pos: [1.93, 0.62, -2.62], rotY: 0, scale: 0.8 }, // tune to sit on a shelf board
  horse:         { model: 'horse_statue_01', pos: [2.15, 1.125, -2.58], rotY: 0.5 },     // CLUE (digit under its base)
  console:       { model: 'ClassicConsole_01', pos: [3.18, 0, 0.15], rotY: -PI / 2 },
  lockedBox:     { model: 'CheeseBox_01', pos: [3.12, 0.949, 0.15], rotY: -PI / 2, scale: 1.7 }, // the "coffret" with 4-digit lock
  chairA:        { model: 'painted_wooden_chair_02', pos: [3.12, 0, -1.05], rotY: -PI / 2 },
  chairB:        { model: 'painted_wooden_chair_02', pos: [3.12, 0, 1.4], rotY: -PI / 2 },
  roundFrame:    { model: 'hanging_picture_frame_03', pos: [3.48, 1.62, 0.15], rotY: -PI / 2 },
  sofaPainting:  { model: 'fancy_picture_frame_01', pos: [0.25, 1.65, 2.74], rotY: PI },
  rockingChair:  { model: 'Rockingchair_01', pos: [2.55, -0.102, 1.95], rotY: -2.2 },     // rocks by itself at scripted moments
  kidTable:      { model: 'side_table_01', pos: [-2.0, 0, 0.2], rotY: 0 },
  kidChair:      { model: 'painted_wooden_chair_01', pos: [-2.0, 0, 0.75], rotY: PI, scale: 0.72 },
  duck:          { model: 'rubber_duck_toy', pos: [-1.35, 0, 0.95], rotY: 0.8, scale: 0.6 }, // CLUE (digit under it)
  alarmClock:    { model: 'alarm_clock_01', pos: [0.55, 0.533, 0.92], rotY: -0.4 },
  fan:           { model: 'ceiling_fan', pos: [FAN.x, 2.5, FAN.z], rotY: 0 },
  // Alcove (buanderie)
  alcoveCabinet: { model: 'painted_wooden_cabinet', pos: [1.0, 0, -4.28], rotY: 0 },    // battery #2 in drawer_01
  powerBox:      { model: 'power_box_01', pos: [2.6, 1.45, -4.553], rotY: 0 },          // breaker panel; door must start CLOSED
  alcoveShelf:   { model: 'Shelf_01', pos: [3.5, 0, -3.7], rotY: -PI / 2 },
  boxA:          { model: 'cardboard_box_01', pos: [2.0, 0, -4.3], rotY: 0.2 },
  boxB:          { model: 'cardboard_box_01', pos: [2.05, 0.335, -4.28], rotY: -0.3, scale: 0.85 },
  boxC:          { model: 'cardboard_box_01', pos: [-3.05, 0, -1.0], rotY: 1.2 },          // inside the closet
  bulb:          { model: 'lightbulb_01', pos: [1.8, 2.28, -3.6], rotY: 0 },                // broken bulb hanging in alcove
  cassette:      { model: 'portable_cassette_player', pos: [-1.95, 0.551, 0.12], rotY: 0.3 }, // on kid table (flavor)
};

// Pickup spawn points (world positions of item origins).
export const ITEMS = {
  note1:      { pos: [0.05, 0.536, 1.0], rotY: 0.25 },     // on the coffee table
  flashlight: { inside: 'dresser.drawerTop' },              // inside top drawer of the dresser
  battery1:   { inside: 'endTable.drawer' },
  battery2:   { inside: 'alcoveCabinet.drawer_01' },
  key:        { inside: 'lockedBox' },
  note2:      { pos: [-2.05, 0.552, 0.3], rotY: -0.2 },     // child drawing on the kid table
  note3:      { inside: 'alcoveCabinet.door_01' },          // old newspaper clipping in the cabinet
};

// Player spawn (standing in front of the sofa, looking at the TV).
export const SPAWN = { x: 0.25, z: 1.5, yaw: 0 }; // yaw 0 = looking toward -Z (north)

// Navigation graph for the entity. Nodes are on walkable floor, links are straight walkable segments.
// y is computed from groundHeightAt. Keep props clear of these points and the straight lines between linked nodes.
export const NAV_NODES = {
  hall:          { x: -3.0, z: -3.6, upper: true },  // behind the upstairs door (entity "home")
  landing:       { x: -3.0, z: -2.3, upper: true },
  stairsTop:     { x: -3.0, z: -1.6 },
  stairsMid:     { x: -3.0, z: -0.1 },
  stairsBottom:  { x: -3.0, z: 2.05 },
  swCorner:      { x: -2.2, z: 2.1 },
  kidCorner:     { x: -1.0, z: 0.0 },
  closetFront:   { x: -2.0, z: -1.9 },
  tvFront:       { x: -0.6, z: -1.55 },
  center:        { x: 0.9, z: -0.45 },
  sofaFront:     { x: -0.6, z: 1.35 },
  sofaEast:      { x: 1.55, z: 1.25 },
  alcoveDoor:    { x: 1.35, z: -2.35 },
  alcoveIn:      { x: 1.35, z: -3.5 },
  alcoveEast:    { x: 2.7, z: -3.6 },
  clockFront:    { x: 2.6, z: -1.75 },
  consoleFront:  { x: 2.35, z: 0.15 },
  rocking:       { x: 1.95, z: 1.0 },
};
export const NAV_LINKS = [
  ['hall', 'landing'], ['landing', 'stairsTop'], ['stairsTop', 'stairsMid'], ['stairsMid', 'stairsBottom'],
  ['stairsBottom', 'swCorner'], ['swCorner', 'sofaFront'], ['swCorner', 'kidCorner'],
  ['kidCorner', 'closetFront'], ['kidCorner', 'tvFront'], ['kidCorner', 'sofaFront'], ['kidCorner', 'center'],
  ['closetFront', 'tvFront'], ['tvFront', 'center'], ['tvFront', 'alcoveDoor'],
  ['center', 'alcoveDoor'], ['center', 'clockFront'], ['center', 'consoleFront'], ['center', 'sofaEast'], ['center', 'rocking'],
  ['alcoveDoor', 'alcoveIn'], ['alcoveIn', 'alcoveEast'],
  ['clockFront', 'consoleFront'], ['consoleFront', 'rocking'], ['rocking', 'sofaEast'],
];

// Geometry helper: generic floor height (walkable surfaces).
// prevY (optional) = the caller's current floor height; it disambiguates the closet under the stairs
// (only reachable through the hide interaction). Without prevY the stairs/landing win.
export function groundHeightAt(x, z, prevY) {
  const hasPrev = typeof prevY === 'number';
  // Upper hallway behind the upstairs door
  if (x >= UPPER_HALL.minX && x <= UPPER_HALL.maxX && z < ROOM.minZ && z >= UPPER_HALL.minZ && (!hasPrev || prevY > 1.5)) return UPPER.floorY;
  // Closet under the stairs
  if (hasPrev && prevY < 1.0 && x >= CLOSET.minX && x <= CLOSET.maxX && z >= CLOSET.minZ && z <= CLOSET.maxZ) return 0;
  const s = stairHeightAt(x, z);
  if (s !== null) return s;
  return 0;
}
