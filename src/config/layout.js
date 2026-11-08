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
  // boxA / boxB stand on the boards of the north steel shelf (DETAIL_PROPS.shelfN, batch 3); Details.js re-seats them
  boxA:          { model: 'cardboard_box_01', pos: [1.92, 0.133, -4.34], rotY: PI / 2 + 0.05 },                // bottom board of shelfN
  boxB:          { model: 'cardboard_box_01', pos: [1.92, 0.639, -4.33], rotY: -PI / 2 + 0.08, scale: 0.85 }, // board 2 of shelfN
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

// Batch-2 set dressing (Poly Haven), placed by the detail pass. See assets/NEW_ASSETS.md §3 for the checks behind
// these positions. `keepNodes` / `hideNodes` select one variant inside multi-variant models; rotX/rotZ tilt leaning props.
export const EXTRA_PROPS = {
  boombox:      { model: 'boombox', pos: [-2.35, 0, -0.50], rotY: PI / 2 },
  gamepad:      { model: 'gamepad', pos: [-0.30, 0, -1.95], rotY: 0.5, noCollider: true },
  bat:          { model: 'baseball_bat', pos: [-3.40, 0.254, 2.63], rotY: 0, rotX: 0.10, rotZ: 0.10 },
  football:     { model: 'football', pos: [-2.35, 0.007, 1.15], rotY: 0.7, hideNodes: ['football_inflated'], zeroNodeX: 'football_deflated' },
  mirror:       { model: 'ornate_mirror_01', pos: [0.47, 1.62, -2.749], rotY: 0, noCollider: true },
  stairPhotoA:  { model: 'hanging_picture_frame_02', pos: [-3.498, 2.55, 0.30], rotY: PI / 2, noCollider: true },
  stairPhotoB:  { model: 'hanging_picture_frame_02', pos: [-3.498, 3.50, -0.75], rotY: PI / 2, noCollider: true },
  oldTv:        { model: 'Television_01', pos: [2.55, 0, -4.33], rotY: 0 },
  socket:       { model: 'pull_chain_light_socket', pos: [1.80, 2.50, -3.60], rotY: 0, noCollider: true },
  toolbox:      { model: 'metal_toolbox', pos: [3.20, 0, -4.38], rotY: -PI / 2 },
  laundry:      { model: 'plastic_crate_02', pos: [0.636, 0.133, -3.165], rotY: PI / 2 + 0.04, noCollider: true }, // bottom board of DETAIL_PROPS.shelfW
  stool:        { model: 'painted_wooden_stool', pos: [0.62, 0, -3.72], rotY: 0 },
  broom:        { model: 'wooden_broom', pos: [0.29, 0.122, -3.72], rotY: PI / 2, rotZ: 0.12, noCollider: true },
  bleach:       { model: 'bleach_bottle', pos: [0.85, 1.182, -4.30], rotY: -0.3, noCollider: true },
  jug:          { model: 'plastic_bottle_gallon', pos: [0.60, 1.182, -4.36], rotY: 0.5, noCollider: true },
  paintCan:     { model: 'can_rusted', pos: [3.36, 0.66, -3.95], rotY: 1.0, noCollider: true },
  gnome:        { model: 'garden_gnome', pos: [3.25, 0, -3.10], rotY: -1.47 },
  mousetrap:    { model: 'mousetrap', pos: [1.70, 0, -4.03], rotY: 0.3, noCollider: true },                // front-left foot of shelfN
  suitcase:     { model: 'vintage_suitcase', pos: [-3.31, 0, -1.20], rotY: PI / 2, hidePrefix: 'vintage_suitcase_02' },
  suitcaseHall: { model: 'vintage_suitcase', pos: [-3.47, 2.75, -4.356], rotY: PI / 2, hidePrefix: 'vintage_suitcase_01', noCollider: true },
};

// ---------------------------------------------------------------------------------------------------------------------
// Batch-3 detail pass (src/world/Details.js; models in assets/NEW_ASSETS.md §B3). Same conventions as EXTRA_PROPS, plus:
//   on / board: the model rests on that board of a steel shelf (y computed from STEEL_SHELF_BOARDS + the model's bbox)
//   scale: number or [x, y, z]; nodeRot: { node: [x, y, z] } Euler set on a child node; hall: parented to the hallway
//   group (drawn only while the upstairs door is open).
// Built walls (Architecture.js): the nook's south face is the back of the 0.15 m partition, z = ROOM.minZ - 0.15 = -2.9
// (NEW_ASSETS assumed -2.95: shelfW / ladder / N7 / N10 are 5 cm further south here). The ABS drain stack stands at
// (0.31, -3.2) and the doorway jamb at x = 0.9, so the west steel shelf is a 0.52 m-wide unit (x scale 0.88) between them.
// The HVAC trunk (y >= 2.30) runs over shelfW: its top board only takes low items. Both shelves stand 1.4 cm off
// their wall (the tiled wainscot of the nook is a 3 mm overlay).
export const STEEL_SHELF_BOARDS = [0.133, 0.639, 1.145, 1.651, 2.130];
export const DETAIL_PROPS = {
  // ── Nook = storage room ───────────────────────────────────────────────────
  shelfW:      { model: 'steel_frame_shelves_02', pos: [0.636, 0, -3.165], rotY: PI, scale: [0.88, 1, 1] }, // laundry basket on board 0
  shelfWcan:   { model: 'metal_jerrycan', on: 'shelfW', board: 1, pos: [0.64, 0, -3.17], rotY: PI + 0.06 },
  medkit:      { model: 'medical_box', on: 'shelfW', board: 2, pos: [0.63, 0, -3.176], rotY: PI / 2 - 0.03 }, // latch toward the doorway
  milkCrate:   { model: 'plastic_crate_01', on: 'shelfW', board: 3, pos: [0.60, 0, -3.16], rotY: PI / 2 + 0.08 },
  shelfN:      { model: 'steel_frame_shelves_02', pos: [1.92, 0, -4.336], rotY: 0 },                       // boxA board 0, boxB board 1
  shelfNbox3:  { model: 'cardboard_box_01', on: 'shelfN', board: 2, pos: [1.93, 0, -4.35], rotY: PI / 2 - 0.06, scale: 0.8 },
  shelfNbox4:  { model: 'cardboard_box_01', on: 'shelfN', board: 3, pos: [1.90, 0, -4.34], rotY: PI / 2 + 0.12, scale: 0.75 },
  shelfNbox5:  { model: 'cardboard_box_01', on: 'shelfN', board: 4, pos: [1.94, 0, -4.36], rotY: PI / 2 - 0.15, scale: 0.72 },
  tubeLight:   { model: 'mounted_fluorescent_lights', pos: [1.95, 2.51, -3.85], rotY: 0 },                // screwed under the joists
  ladder:      { model: 'wooden_ladder', pos: [2.13, 0.1255, -2.709], rotY: -PI / 2, rotX: -0.25,
                 nodeRot: { wooden_ladder_supports: [0, 0, -0.70] } },                                    // folded, leaning on the S face
  // ── Upstairs hallway (win view) ───────────────────────────────────────────
  hallLamp:    { model: 'hanging_industrial_lamp', pos: [-3.0, 5.2, -4.0], rotY: 0.4, scale: 0.6, hall: true }, // shade bottom 4.63
  hallLantern: { model: 'Lantern_01', pos: [-2.62, 2.75, -4.22], rotY: -0.6, hall: true },
};
// Bulb of hallLamp (scale 0.6): Details moves Lighting's hallway light (doorLight when the door is open) here.
export const HALL_LAMP_BULB = [-3.0, 4.7, -4.0];
// Fluorescent batten light: ONE non-shadow SpotLight created at build, intensity-driven (on only with mains power).
// A spot rather than a point light: without a shadow map a point light in the nook would light the main room's ceiling
// and floor straight through the partition. Aimed down and 25° north, its cone (soft edge) lights the shelves, the
// breaker panel and the nook floor, reaches the doorway threshold, and never points up at the room ceiling.
export const TUBE_LIGHT = { pos: [1.95, 2.46, -3.85], target: [1.95, 0, -5.0], angle: 1.35, penumbra: 0.9, cd: 55 };

// Grime / leak / stain decals (assets/NEW_ASSETS.md §B3.5, positions corrected to the built walls: nook S face z = -2.9,
// closet walls x = -3.5 / z = -2.75, closet ceiling 2.45, nook "ceiling" = subfloor between the joists at 2.75; hall
// decals kept off the runner rug, the window and the bedroom door). pos = centre ON the surface, normal toward the
// viewer, up = texture top direction, size = [w, h] m, tint sRGB hex, opacity, flip = mirror u.
// tex: a batch-3 decal set, or 'crayon:N' = cell N of the procedural crayon-scribble atlas (Details.js).
// Ids: N nook, M main room (batch-3 plan), G main-room grime (scuffs / smudges / leaks), K crayon scribbles, C closet, H hall.
export const DECALS = [
  { id: 'N1', tex: 'decal_leak_streaks', pos: [0.95, 2.05, -4.6], normal: [0, 0, 1], up: [0, 1, 0], size: [1.3, 0.9] },
  { id: 'N2', tex: 'decal_pipe_leak', pos: [2.98, 2.0, -4.6], normal: [0, 0, 1], up: [0, 1, 0], size: [0.45, 0.6] },
  { id: 'N3', tex: 'decal_rust_drip', pos: [2.66, 0.94, -4.6], normal: [0, 0, 1], up: [0, 1, 0], size: [0.12, 0.48] },
  { id: 'N4', tex: 'decal_grime', pos: [2.55, 1.45, -4.6], normal: [0, 0, 1], up: [0, 1, 0], size: [0.9, 0.85], tint: '#b8b0a4' },
  { id: 'N5', tex: 'decal_mold', pos: [0.2, 2.2, -4.25], normal: [1, 0, 0], up: [0, 1, 0], size: [0.7, 0.6] },
  { id: 'N6', tex: 'decal_water_ring', pos: [2.9, 2.75, -3.55], normal: [0, -1, 0], up: [0.4226, 0, -0.9063], size: [0.8, 0.8] },
  { id: 'N7', tex: 'decal_rising_damp', pos: [2.65, 0.28, -2.9], normal: [0, 0, -1], up: [0, 1, 0], size: [1.6, 0.56] },
  { id: 'N8', tex: 'decal_dirt_patch', pos: [2.1, 0, -3.8], normal: [0, 1, 0], up: [0, 0, -1], size: [1.1, 1], tint: '#a08a70', opacity: 0.85 },
  { id: 'N9', tex: 'decal_dirt_patch', pos: [1.35, 0, -3.25], normal: [0, 1, 0], up: [-1, 0, 0], size: [0.8, 0.86], tint: '#a08a70', opacity: 0.7 },
  { id: 'N10', tex: 'decal_scuffs', pos: [3.2, 0.2, -2.9], normal: [0, 0, -1], up: [0, 1, 0], size: [0.55, 0.25], tint: '#2b2622' },
  { id: 'N11', tex: 'decal_mold', pos: [3.5, 0.3, -3.05], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.5, 0.45], flip: true },
  { id: 'M1', tex: 'decal_leak_streaks', pos: [2.45, 1.35, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [1.15, 0.9], opacity: 0.8 },
  { id: 'M2', tex: 'decal_water_ring', pos: [-2.0, 2.5, 1.62], normal: [0, -1, 0], up: [-0.2588, 0, -0.9659], size: [0.85, 0.85] }, // by the stairwell
  { id: 'M3', tex: 'decal_grime', pos: [-0.55, 1.78, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [0.9, 0.6], tint: '#9c958a', opacity: 0.5 },
  { id: 'M4', tex: 'decal_scuffs', pos: [-1.85, 0.22, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [1, 0.3], tint: '#2b2622' },
  { id: 'M5', tex: 'decal_scuffs', pos: [3.5, 0.78, -1.05], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.6, 0.25], tint: '#2b2622', opacity: 0.6 },
  { id: 'M6', tex: 'decal_hand_smudges', pos: [-2.5, 1.0, -1.58], normal: [1, 0, 0], up: [0, 1, 0], size: [0.3, 0.4] },
  { id: 'M7', tex: 'decal_hand_smudges', pos: [-3.5, 2.77, -0.6], normal: [1, 0, 0], up: [0, 0.798, 0.603], size: [1, 0.3] },
  { id: 'M8', tex: 'decal_mold', pos: [-3.15, 0.45, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.65, 0.6] },
  { id: 'M9', tex: 'decal_dirt_patch', pos: [-3.0, 0, 2.1], normal: [0, 1, 0], up: [0, 0, -1], size: [0.9, 0.7], tint: '#8a7660', opacity: 0.6 },
  { id: 'G1', tex: 'decal_scuffs', pos: [0.62, 0.17, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [0.5, 0.22], tint: '#2b2622', opacity: 0.85 },
  { id: 'G2', tex: 'decal_scuffs', pos: [3.5, 0.16, -1.95], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.6, 0.22], tint: '#2b2622', opacity: 0.8, flip: true },
  { id: 'G3', tex: 'decal_scuffs', pos: [3.5, 0.17, -0.45], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.6, 0.24], tint: '#2b2622', opacity: 0.75 },
  { id: 'G4', tex: 'decal_scuffs', pos: [3.5, 0.15, 2.2], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.7, 0.2], tint: '#2b2622', opacity: 0.7, flip: true },
  { id: 'G5', tex: 'decal_scuffs', pos: [-2.0, 0.16, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.5, 0.22], tint: '#2b2622', opacity: 0.8 },
  { id: 'G6', tex: 'decal_scuffs', pos: [-2.5, 0.19, -0.95], normal: [1, 0, 0], up: [0, 1, 0], size: [0.8, 0.25], tint: '#2b2622', opacity: 0.8 },
  { id: 'G7', tex: 'decal_scuffs', pos: [2.35, 0.14, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.45, 0.2], tint: '#2b2622', opacity: 0.7, flip: true },
  { id: 'G8', tex: 'decal_hand_smudges', pos: [-3.5, 1.2, 2.08], normal: [1, 0, 0], up: [0, 1, 0], size: [0.34, 0.4] },          // light switch
  { id: 'G9', tex: 'decal_hand_smudges', pos: [0.77, 1.15, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [0.24, 0.5], flip: true }, // nook jambs
  { id: 'G10', tex: 'decal_hand_smudges', pos: [1.93, 1.2, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [0.24, 0.5] },
  { id: 'G12', tex: 'decal_grime', pos: [1.98, 1.52, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [0.3, 0.26], tint: '#8f877c', opacity: 0.55 }, // thermostat
  { id: 'G13', tex: 'decal_leak_streaks', pos: [-2.7, 2.05, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.7, 0.9], opacity: 0.55, flip: true },
  { id: 'G14', tex: 'decal_grime', pos: [3.1, 0.5, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.7, 0.6], tint: '#8f877c', opacity: 0.45 }, // above the vent
  { id: 'G15', tex: 'decal_hand_smudges', pos: [-2.5, 1.35, -0.2], normal: [1, 0, 0], up: [0, 1, 0], size: [0.3, 0.32], opacity: 0.7, flip: true },
  { id: 'K1', tex: 'crayon:0', pos: [-2.5, 0.62, -0.95], normal: [1, 0, 0], up: [0, 1, 0], size: [0.7, 0.55] },
  { id: 'K2', tex: 'crayon:1', pos: [-2.5, 0.95, -0.1], normal: [1, 0, 0], up: [0, 1, 0], size: [0.42, 0.4] },
  { id: 'K3', tex: 'crayon:2', pos: [-1.95, 0.64, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.6, 0.5] },
  { id: 'K4', tex: 'crayon:3', pos: [-2.62, 0.55, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.44, 0.6] },
  { id: 'K5', tex: 'crayon:4', pos: [-1.45, 0.88, 2.75], normal: [0, 0, -1], up: [0, 1, 0], size: [0.3, 0.25] },
  { id: 'K6', tex: 'crayon:5', pos: [-2.5, 0.35, 0.95], normal: [1, 0, 0], up: [0, 1, 0], size: [0.3, 0.22] },
  { id: 'K7', tex: 'crayon:6', pos: [-1.95, 0.48, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [0.34, 0.28] },
  { id: 'C1', tex: 'decal_grime', pos: [-3.5, 1.25, -2.15], normal: [1, 0, 0], up: [0, 1, 0], size: [0.8, 0.8], tint: '#8f877c' },
  { id: 'C2', tex: 'decal_mold', pos: [-3.5, 0.3, -0.75], normal: [1, 0, 0], up: [0, 1, 0], size: [0.6, 0.45] },
  { id: 'C3', tex: 'decal_leak_streaks', pos: [-3.03, 2.0, -2.75], normal: [0, 0, 1], up: [0, 1, 0], size: [0.8, 0.9] },
  { id: 'C4', tex: 'decal_hand_smudges', pos: [-2.6, 1.05, -1.58], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.28, 0.38] },
  { id: 'C5', tex: 'decal_dirt_patch', pos: [-3.05, 0, -1.9], normal: [0, 1, 0], up: [0, 0, -1], size: [0.75, 0.9], tint: '#8a7660', opacity: 0.8 },
  { id: 'H1', tex: 'decal_water_ring', pos: [-3.03, 5.2, -3.35], normal: [0, -1, 0], up: [0.6428, 0, -0.766], size: [0.75, 0.75] },
  { id: 'H2', tex: 'decal_leak_streaks', pos: [-2.45, 4.75, -3.165], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.5, 0.9] },
  { id: 'H3', tex: 'decal_mold', pos: [-2.68, 4.98, -4.4], normal: [0, 0, 1], up: [0, 1, 0], size: [0.45, 0.44] },
  { id: 'H4', tex: 'decal_scuffs', pos: [-3.6, 2.95, -3.2], normal: [1, 0, 0], up: [0, 1, 0], size: [0.9, 0.3], tint: '#2b2622' },
  { id: 'H5', tex: 'decal_dirt_patch', pos: [-2.6, 2.75, -3.15], normal: [0, 1, 0], up: [0, 0, -1], size: [0.3, 0.75], tint: '#7a6450', opacity: 0.6 },
  { id: 'H6', tex: 'decal_dirt_patch', pos: [-2.7, 2.75, -4.05], normal: [0, 1, 0], up: [1, 0, 0], size: [0.5, 0.3], tint: '#7a6450', opacity: 0.55, flip: true },
  { id: 'H7', tex: 'decal_grime', pos: [-3.6, 3.3, -3.0], normal: [1, 0, 0], up: [0, 1, 0], size: [0.5, 0.7], tint: '#8f877c', opacity: 0.5 },
];
