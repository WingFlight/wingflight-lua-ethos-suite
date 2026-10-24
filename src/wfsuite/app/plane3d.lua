-- The 3D plane: a low-poly aircraft drawn at a given attitude inside a box.
-- Used by the Alignment page (app/alignment_visual.lua) and the Setup
-- Wizard (its Sensors step, and app/setup_wizard_art.lua's pictures).
--
--   plane3d.setup(spec)        -- which airframe (default: the Extra below)
--   plane3d.pose(arrows)       -- light up and deflect control surfaces
--   plane3d.draw(x, y, w, h, roll, pitch, yaw[, zoom])
--   local ux, uy = plane3d.noseDirection(roll, pitch, yaw)
--
-- Angles are degrees in MSP_ATTITUDE's sense. Yaw 0 shows the model from
-- behind (tail towards the viewer), as the pilot sees it standing behind
-- the model; callers that follow the live heading subtract their own
-- reference yaw first. draw() sizes the model so it fits the box in any
-- attitude (at zoom 1) and clips to the box.
--
-- The default airframe is the Configurator's model (wingflight-configurator
-- resources/models/model.gltf, an Extra-style aerobatic plane): red body,
-- dark ailerons/elevator/rudder, white spinner and landing gear, a canopy
-- and a two-blade prop. setup() builds other layouts from the same parts:
--
--   spec.tail     "conventional" (stabilizer, elevator, fin) | "vtail" | "none"
--   spec.wing     "straight" | "swept" (flying wing) | "delta"
--   spec.outer    {from, to}: ailerons/elevons along the half span (0 the
--                 centreline, 1 the tip), or nil for none
--   spec.inner    {from, to}: flaps, or nil
--   spec.fin, spec.rudder, spec.winglets, spec.gear   booleans
--
-- Control surfaces are groups: "outer", "inner", "stab", "vtail" (one per
-- side: 1 is the left as seen from behind, 2 the right) and "fin" (1).
-- pose() takes the Setup Wizard's arrows in that shape ({outer = {"down",
-- "up"}, fin = {"right"}, ...}, app/setup_wizard_art.lua): a surface with
-- an arrow is drawn in the highlight colour and swung DEFLECT degrees about
-- its hinge, trailing edge the way the arrow points, with an arrow drawn
-- beside it; "lit" lights a surface at neutral with no arrow. The rest sit
-- at neutral in the surface colour.
--
-- The mesh is written in the glTF file's own coordinates (x = span, y = up,
-- z = aft) so its numbers can be checked against it, and converted once, at
-- setup, to this renderer's X = nose(+)/tail(-), Y = span (+ is the left
-- seen from behind), Z = up(+)/down(-).
--
-- Rendering, per paint: the attitude becomes one rotation matrix (built by
-- passing the three axes through rotatePoint(), the orientation the
-- Alignment page was tuned with), every vertex is rotated and projected
-- once into reused buffers, faces of closed parts that point away from the
-- camera are dropped, the rest are flat-shaded from a fixed light and drawn
-- far-to-near. The camera sits CAMERA_ELEVATION above the model's level
-- plane, so the top of a level aircraft stays visible instead of the wings
-- collapsing to a line. No tables are allocated per paint; shaded colours
-- are built once per theme, the mesh once per setup().

if package.loaded["wfsuite.app.plane3d"] then
  return package.loaded["wfsuite.app.plane3d"]
end

local cos = math.cos
local sin = math.sin
local rad = math.rad
local floor = math.floor
local sqrt = math.sqrt
local max = math.max
local min = math.min
local t_sort = table.sort

local BASE_VIEW_PITCH_R = rad(-90)
local BASE_VIEW_YAW_R = rad(90)
local CAMERA_DIST = 7.0
local CAMERA_NEAR_EPS = 0.25
local CAMERA_ELEVATION_R = rad(18)
local CAM_EC = cos(CAMERA_ELEVATION_R)
local CAM_ES = sin(CAMERA_ELEVATION_R)

local function rotatePoint(x, y, z, pitchR, yawR, rollR)
  local cbp = cos(BASE_VIEW_PITCH_R)
  local sbp = sin(BASE_VIEW_PITCH_R)
  local px = x
  local py = y * cbp - z * sbp
  local pz = y * sbp + z * cbp

  local cby = cos(BASE_VIEW_YAW_R)
  local sby = sin(BASE_VIEW_YAW_R)
  local bx = px * cby + pz * sby
  local by = py
  local bz = -px * sby + pz * cby

  local cz = cos(rollR)
  local sz = sin(rollR)
  local cx = cos(pitchR)
  local sx = sin(pitchR)
  local cy = cos(yawR)
  local sy = sin(yawR)

  local x1 = bx * cz - by * sz
  local y1 = bx * sz + by * cz
  local z1 = bz

  local x2 = x1
  local y2 = y1 * cx - z1 * sx
  local z2 = y1 * sx + z1 * cx

  local x3 = x2 * cy + z2 * sy
  local y3 = y2
  local z3 = -x2 * sy + z2 * cy

  return x3, y3, z3
end

---------------------------------------------------------------------------
-- Mesh
---------------------------------------------------------------------------

-- glTF -> renderer: scale, and the glTF point that becomes the origin
-- (roughly the middle of the airframe, so it turns about its centre).
local MODEL_SCALE = 0.70
local ORIGIN_Y = 0.10
local ORIGIN_Z = 1.00

local MAT_BODY = 1
local MAT_SURFACE = 2
local MAT_WHITE = 3
local MAT_CANOPY = 4
local MAT_PROP = 5
local MAT_ACTIVE = 6

-- How far pose() swings a surface with an arrow.
local DEFLECT_R = rad(28)

local MX, MY, MZ = {}, {}, {}
local vertexCount = 0

-- Faces: up to four vertex indices (FD = 0 for a triangle), a material,
-- and whether the face is a flat plate seen from both sides (wings, tail,
-- prop, gear legs) or one side of a closed part (culled when facing away).
local FA, FB, FC, FD, FMAT, FTWO = {}, {}, {}, {}, {}, {}
local faceCount = 0

-- Control surfaces, one entry per plate: its group and side, its face, the
-- hinge vertices (H1, H2), the trailing vertices (T1, T2) and their neutral
-- positions (RX/RY/RZ, indexed by vertex).
local SGROUP, SSIDE, SFACE, SH1, SH2, ST1, ST2 = {}, {}, {}, {}, {}, {}, {}
local RX, RY, RZ = {}, {}, {}
local surfaceCount = 0

local MODEL_RADIUS = 1

local function vtx(gx, gy, gz)
  vertexCount = vertexCount + 1
  MX[vertexCount] = -(gz - ORIGIN_Z) * MODEL_SCALE
  MY[vertexCount] = gx * MODEL_SCALE
  MZ[vertexCount] = (gy - ORIGIN_Y) * MODEL_SCALE
  return vertexCount
end

local function pushFace(a, b, c, d, mat, twoSided)
  faceCount = faceCount + 1
  FA[faceCount], FB[faceCount], FC[faceCount], FD[faceCount] = a, b, c, d or 0
  FMAT[faceCount] = mat
  FTWO[faceCount] = twoSided
end

local function plate(a, b, c, d, mat)
  pushFace(a, b, c, d, mat, true)
end

-- A control surface: hinge h1-h2, trailing edge t2-t1 (a plate, drawn
-- h1, h2, t2, t1).
local function surface(group, side, h1, h2, t2, t1)
  pushFace(h1, h2, t2, t1, MAT_SURFACE, true)
  surfaceCount = surfaceCount + 1
  SGROUP[surfaceCount], SSIDE[surfaceCount], SFACE[surfaceCount] = group, side, faceCount
  SH1[surfaceCount], SH2[surfaceCount], ST1[surfaceCount], ST2[surfaceCount] = h1, h2, t1, t2
  RX[t1], RY[t1], RZ[t1] = MX[t1], MY[t1], MZ[t1]
  RX[t2], RY[t2], RZ[t2] = MX[t2], MY[t2], MZ[t2]
end

-- One face of a closed part. (rx, ry, rz) is a glTF point inside the part
-- next to this face; the winding is flipped if needed so the normal points
-- away from it, which is all the back-face test needs.
local function solid(a, b, c, d, mat, rx, ry, rz)
  local ix = -(rz - ORIGIN_Z) * MODEL_SCALE
  local iy = rx * MODEL_SCALE
  local iz = (ry - ORIGIN_Y) * MODEL_SCALE
  local ux, uy, uz = MX[b] - MX[a], MY[b] - MY[a], MZ[b] - MZ[a]
  local vx, vy, vz = MX[c] - MX[a], MY[c] - MY[a], MZ[c] - MZ[a]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local n = d and 4 or 3
  local gx = (MX[a] + MX[b] + MX[c] + (d and MX[d] or 0)) / n - ix
  local gy = (MY[a] + MY[b] + MY[c] + (d and MY[d] or 0)) / n - iy
  local gz = (MZ[a] + MZ[b] + MZ[c] + (d and MZ[d] or 0)) / n - iz
  if nx * gx + ny * gy + nz * gz < 0 then
    if d then a, b, c, d = a, d, c, b else b, c = c, b end
  end
  pushFace(a, b, c, d, mat, false)
end

-- Fuselage stations: {z, half width, bottom y, top y, side y}. The full
-- body runs to a tail post; a tailless model's pod ends behind the wing.
local BODY = {
  {-1.62, 0.36, -0.20, 0.30, 0.05},
  {-1.00, 0.54, -0.42, 0.38, 0.00},
  {-0.30, 0.60, -0.46, 0.46, 0.00},
  { 1.00, 0.50, -0.30, 0.50, 0.05},
  { 1.80, 0.30, -0.22, 0.62, 0.12},
  { 3.55, 0.05, -0.04, 0.40, 0.18},
}
local POD = {
  {-1.62, 0.36, -0.20, 0.30, 0.05},
  {-1.00, 0.50, -0.38, 0.38, 0.00},
  {-0.30, 0.55, -0.40, 0.44, 0.00},
  { 0.90, 0.45, -0.28, 0.48, 0.05},
  { 1.70, 0.22, -0.14, 0.34, 0.08},
  { 2.35, 0.04, -0.02, 0.12, 0.06},
}

-- Wing planforms, glTF units: root and tip as {x, leading edge z, trailing
-- edge z, y}.
local WINGS = {
  straight = {root = {0.55, -0.55, 1.00, -0.12}, tip = {3.55, -0.33, 0.76, -0.06}},
  swept = {root = {0.45, -0.95, 1.30, -0.06}, tip = {3.60, 1.55, 2.25, 0.10}},
  delta = {root = {0.45, -1.25, 2.05, -0.08}, tip = {3.00, 1.75, 2.05, -0.02}},
}

local function fuselage(stations)
  local ring = {}
  for i = 1, #stations do
    local s = stations[i]
    local z, w, yb, yt, ym = s[1], s[2], s[3], s[4], s[5]
    local t = w * 0.65
    ring[i] = {
      vtx(-t, yt, z), vtx(t, yt, z), vtx(w, ym, z),
      vtx(t, yb, z), vtx(-t, yb, z), vtx(-w, ym, z),
    }
  end
  for i = 1, #stations - 1 do
    local r0, r1 = ring[i], ring[i + 1]
    local s0, s1 = stations[i], stations[i + 1]
    local rz = (s0[1] + s1[1]) * 0.5
    local ry = (s0[5] + s1[5]) * 0.5
    for k = 1, 6 do
      local k2 = (k % 6) + 1
      solid(r0[k], r0[k2], r1[k2], r1[k], MAT_BODY, 0, ry, rz)
    end
  end
  local first, last = stations[1], stations[#stations]
  local f, l = ring[1], ring[#stations]
  solid(f[1], f[2], f[3], f[4], MAT_BODY, 0, first[5], first[1] + 1)
  solid(f[4], f[5], f[6], f[1], MAT_BODY, 0, first[5], first[1] + 1)
  solid(l[1], l[2], l[3], l[4], MAT_BODY, 0, last[5], last[1] - 1)
  solid(l[4], l[5], l[6], l[1], MAT_BODY, 0, last[5], last[1] - 1)
end

-- Canopy: windscreen point on the deck, two upper corners, two lower
-- corners, and a tail point that runs into the deck behind.
local function canopy(rearY, rearZ)
  local cF = vtx(0, 0.47, 0.20)
  local cBL, cBR = vtx(-0.27, 0.49, 0.80), vtx(0.27, 0.49, 0.80)
  local cTL, cTR = vtx(-0.16, 0.76, 0.85), vtx(0.16, 0.76, 0.85)
  local cR = vtx(0, rearY, rearZ)
  solid(cF, cBR, cTR, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cF, cTR, cTL, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cF, cTL, cBL, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cBR, cR, cTR, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cTR, cR, cTL, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cTL, cR, cBL, nil, MAT_CANOPY, 0, 0.55, 0.9)
end

-- Spinner (a six-sided cone in front of the cowl) and a two-blade prop.
local function nose()
  local tip = vtx(0, 0.05, -2.04)
  local base = {}
  for k = 1, 6 do
    local a = (k - 1) * math.pi / 3
    base[k] = vtx(0.2 * cos(a), 0.05 + 0.2 * sin(a), -1.64)
  end
  for k = 1, 6 do
    solid(tip, base[k], base[(k % 6) + 1], nil, MAT_WHITE, 0, 0.05, -1.75)
  end
  plate(vtx(0.12, 0.11, -1.70), vtx(0.95, 0.08, -1.70), vtx(0.95, 0.02, -1.70), vtx(0.12, -0.01, -1.70), MAT_PROP)
  plate(vtx(-0.12, 0.11, -1.70), vtx(-0.95, 0.08, -1.70), vtx(-0.95, 0.02, -1.70), vtx(-0.12, -0.01, -1.70), MAT_PROP)
end

local function lerp(a, b, u) return a + (b - a) * u end

-- A wing panel on one side (side 1: +x, the left seen from behind; side
-- 2: -x), split into spanwise strips at the edges of its surfaces. Each
-- strip is a fixed part (leading edge to hinge) and an aft part (hinge to
-- trailing edge): a control surface where outer/inner covers the strip,
-- fixed wing elsewhere. Surfaces take a chord of 0.25 + 0.1 of the local
-- chord, at most 80% of it.
local function wing(planform, outer, inner, side)
  local root, tip = planform.root, planform.tip
  local sx = (side == 1) and 1 or -1
  local t0 = root[1] / tip[1]
  local cuts = {t0, 1}
  local function cut(t)
    if t and t > t0 + 0.01 and t < 0.99 then cuts[#cuts + 1] = t end
  end
  if outer then cut(outer[1]); cut(outer[2]) end
  if inner then cut(inner[1]); cut(inner[2]) end
  table.sort(cuts)
  local function at(t)
    local x = t * tip[1]
    local u = (x - root[1]) / (tip[1] - root[1])
    if u < 0 then u = 0 elseif u > 1 then u = 1 end
    local le, te, y = lerp(root[2], tip[2], u), lerp(root[3], tip[3], u), lerp(root[4], tip[4], u)
    local chord = te - le
    local hinge = te - min(0.25 + 0.1 * chord, 0.8 * chord)
    return x * sx, y, le, hinge, te
  end
  local prevLE, prevH
  local px, py, ple, ph, pte
  for i = 1, #cuts do
    local t = cuts[i]
    if i > 1 and t - cuts[i - 1] > 0.005 then
      local x, y, le, hinge, te = at(t)
      local lev, hv = vtx(x, y, le), vtx(x, y, hinge)
      plate(prevLE, lev, hv, prevH, MAT_BODY)
      local mid = (cuts[i - 1] + t) * 0.5
      local group = nil
      if outer and mid > outer[1] and mid < outer[2] then group = "outer"
      elseif inner and mid > inner[1] and mid < inner[2] then group = "inner" end
      local h1, h2 = vtx(px, py, ph), vtx(x, y, hinge)
      local t2, t1 = vtx(x, y, te), vtx(px, py, pte)
      if group then surface(group, side, h1, h2, t2, t1) else plate(h1, h2, t2, t1, MAT_BODY) end
      prevLE, prevH = lev, hv
      px, py, ple, ph, pte = x, y, le, hinge, te
    elseif i == 1 then
      local x, y, le, hinge, te = at(t)
      prevLE, prevH = vtx(x, y, le), vtx(x, y, hinge)
      px, py, ple, ph, pte = x, y, le, hinge, te
    end
  end
end

-- Fin with a rudder (or one plain fin when there is none): base leading
-- edge z, fin top y, hinge z, rudder trailing edge z.
local function fin(baseY, baseLE, topY, topLE, hingeZ, teTop, teBottom, bottomY, rudder)
  plate(vtx(0, baseY, baseLE), vtx(0, topY, topLE), vtx(0, topY, hingeZ), vtx(0, bottomY + 0.3, hingeZ), MAT_BODY)
  local h1, h2 = vtx(0, bottomY, hingeZ), vtx(0, topY, hingeZ)
  local t2, t1 = vtx(0, topY, teTop), vtx(0, bottomY, teBottom)
  if rudder then surface("fin", 1, h1, h2, t2, t1) else plate(h1, h2, t2, t1, MAT_BODY) end
end

local DEFAULT_SPEC = {tail = "conventional", wing = "straight", outer = {0.30, 1.0},
  fin = true, rudder = true, gear = true}

local function build(spec)
  local oldVertices, oldFaces = vertexCount, faceCount
  vertexCount, faceCount, surfaceCount = 0, 0, 0
  local tail = spec.tail or "conventional"
  local tailless = tail == "none"

  fuselage(tailless and POD or BODY)
  if tailless then canopy(0.46, 1.45) else canopy(0.62, 1.75) end
  nose()

  local planform = WINGS[spec.wing or "straight"] or WINGS.straight
  wing(planform, spec.outer, spec.inner, 1)
  wing(planform, spec.outer, spec.inner, 2)

  for side = 1, 2 do
    local s = (side == 1) and 1 or -1
    if tail == "conventional" then
      plate(vtx(0.10 * s, 0.36, 2.92), vtx(1.55 * s, 0.36, 3.08), vtx(1.55 * s, 0.36, 3.47), vtx(0.10 * s, 0.36, 3.47), MAT_BODY)
      surface("stab", side, vtx(0.04 * s, 0.36, 3.47), vtx(1.60 * s, 0.36, 3.47), vtx(1.60 * s, 0.36, 3.80), vtx(0.04 * s, 0.36, 3.86))
    elseif tail == "vtail" then
      -- Two surfaces at about 40 degrees, ruddervators on their trailing
      -- edges.
      local rx, ry, tx, ty = 0.06 * s, 0.40, 1.15 * s, 1.30
      plate(vtx(rx, ry, 2.80), vtx(tx, ty, 3.20), vtx(tx, ty, 3.55), vtx(rx, ry, 3.40), MAT_BODY)
      surface("vtail", side, vtx(rx, ry, 3.40), vtx(tx, ty, 3.55), vtx(tx, ty, 3.85), vtx(rx, ry, 3.90))
    end
    if spec.winglets then
      local x, _, _, y = planform.tip[1] * s, nil, nil, planform.tip[4]
      local le, te = planform.tip[2], planform.tip[3]
      plate(vtx(x, y, le), vtx(x, y + 0.65, le + 0.40), vtx(x, y + 0.65, te), vtx(x, y, te), MAT_BODY)
    end
    if spec.gear then
      -- A leg out of the belly and a spatted wheel.
      local px = 0.76 * s
      plate(vtx(0.25 * s, -0.40, -0.52), vtx(px, -0.82, -0.54), vtx(px, -0.82, -0.38), vtx(0.25 * s, -0.40, -0.25), MAT_WHITE)
      local front = vtx(px, -0.93, -0.92)
      local rear = vtx(px, -0.90, -0.10)
      local around = {
        vtx(px, -0.77, -0.50), vtx(px + 0.08, -0.92, -0.50),
        vtx(px, -1.06, -0.50), vtx(px - 0.08, -0.92, -0.50),
      }
      for k = 1, 4 do
        local k2 = (k % 4) + 1
        solid(front, around[k], around[k2], nil, MAT_WHITE, px, -0.92, -0.50)
        solid(rear, around[k2], around[k], nil, MAT_WHITE, px, -0.92, -0.50)
      end
    end
  end

  if spec.fin then
    if tailless then
      fin(0.40, 1.15, 1.05, 1.70, 1.95, 2.25, 2.40, 0.10, spec.rudder)
    elseif tail == "conventional" then
      fin(0.48, 2.85, 1.25, 3.28, 3.52, 3.84, 4.14, -0.02, spec.rudder)
    end
  end

  -- Free what a bigger airframe used before.
  for i = vertexCount + 1, oldVertices do MX[i], MY[i], MZ[i], RX[i], RY[i], RZ[i] = nil, nil, nil, nil, nil, nil end
  for i = faceCount + 1, oldFaces do FA[i], FB[i], FC[i], FD[i], FMAT[i], FTWO[i] = nil, nil, nil, nil, nil, nil end

  MODEL_RADIUS = 0
  for i = 1, vertexCount do
    MODEL_RADIUS = max(MODEL_RADIUS, sqrt(MX[i] * MX[i] + MY[i] * MY[i] + MZ[i] * MZ[i]))
  end
end

-- Swing surface k's trailing edge by angle (radians) towards (dx, dy, dz)
-- (renderer axes), about its hinge; 0 puts it back to neutral.
local function deflect(k, angle, dx, dy, dz)
  local h1, h2 = SH1[k], SH2[k]
  local ax, ay, az = MX[h2] - MX[h1], MY[h2] - MY[h1], MZ[h2] - MZ[h1]
  local al = sqrt(ax * ax + ay * ay + az * az)
  ax, ay, az = ax / al, ay / al, az / al
  -- The plate's normal, turned to face the way the edge should go.
  local t = ST1[k]
  local ux, uy, uz = RX[t] - MX[h1], RY[t] - MY[h1], RZ[t] - MZ[h1]
  local nx, ny, nz = ay * uz - az * uy, az * ux - ax * uz, ax * uy - ay * ux
  local nl = sqrt(nx * nx + ny * ny + nz * nz)
  if nl > 0 then nx, ny, nz = nx / nl, ny / nl, nz / nl end
  if nx * dx + ny * dy + nz * dz < 0 then nx, ny, nz = -nx, -ny, -nz end
  local c, s = cos(angle), sin(angle)
  for j = 1, 2 do
    local v = (j == 1) and ST1[k] or ST2[k]
    local px, py, pz = RX[v] - MX[h1], RY[v] - MY[h1], RZ[v] - MZ[h1]
    local along = px * ax + py * ay + pz * az
    local rx, ry, rz = px - ax * along, py - ay * along, pz - az * along
    local r = sqrt(rx * rx + ry * ry + rz * rz)
    MX[v] = MX[h1] + ax * along + rx * c + nx * r * s
    MY[v] = MY[h1] + ay * along + ry * c + ny * r * s
    MZ[v] = MZ[h1] + az * along + rz * c + nz * r * s
  end
end

-- Arrow -> direction the trailing edge goes, renderer axes. "right" is the
-- right as seen from behind: -Y.
local DIRECTIONS = {
  up = {0, 0, 1, 1}, down = {0, 0, 1, -1},
  right = {0, -1, 0, 1}, left = {0, -1, 0, -1},
  -- Lit at neutral, no arrow: "this is the surface".
  lit = {0, 0, 1, 0},
}

local currentSpec, currentArrows = nil, nil
local NO_ARROWS = {}

-- Each surface's arrow (a DIRECTIONS entry), or false: drawn by draw().
local SDIR = {}

local function applyPose(arrows)
  for k = 1, surfaceCount do
    local dirs = arrows[SGROUP[k]]
    local d = dirs and DIRECTIONS[dirs[SSIDE[k]]]
    SDIR[k] = d or false
    if d then
      FMAT[SFACE[k]] = MAT_ACTIVE
      deflect(k, DEFLECT_R * d[4], d[1], d[2], d[3])
    else
      FMAT[SFACE[k]] = MAT_SURFACE
      deflect(k, 0, 0, 0, 1)
    end
  end
  for k = surfaceCount + 1, #SDIR do SDIR[k] = nil end
end

build(DEFAULT_SPEC)
currentSpec = DEFAULT_SPEC

---------------------------------------------------------------------------
-- Shading
---------------------------------------------------------------------------

-- Light from above, to the left and in front of the screen (view space:
-- x right, y up, z towards the viewer).
local LIGHT_X, LIGHT_Y, LIGHT_Z
do
  local lx, ly, lz = -0.45, 0.75, 0.50
  local l = sqrt(lx * lx + ly * ly + lz * lz)
  LIGHT_X, LIGHT_Y, LIGHT_Z = lx / l, ly / l, lz / l
end
local AMBIENT = 0.45
local DIFFUSE = 0.65
local SHADE_LEVELS = 8

local BASE_COLORS = {
  dark = {
    [MAT_BODY] = {210, 40, 45},
    [MAT_SURFACE] = {78, 80, 88},
    [MAT_WHITE] = {235, 235, 230},
    [MAT_CANOPY] = {95, 125, 160},
    [MAT_PROP] = {160, 160, 165},
    [MAT_ACTIVE] = {255, 165, 30},
  },
  light = {
    [MAT_BODY] = {200, 30, 35},
    [MAT_SURFACE] = {45, 45, 52},
    [MAT_WHITE] = {215, 215, 210},
    [MAT_CANOPY] = {55, 75, 100},
    [MAT_PROP] = {120, 120, 125},
    [MAT_ACTIVE] = {255, 150, 0},
  },
}

local shadeCache = {}

local function shadeTable(isDark)
  local key = isDark and "dark" or "light"
  local cached = shadeCache[key]
  if cached then return cached end
  cached = {}
  for mat, rgb in pairs(BASE_COLORS[key]) do
    local levels = {}
    for i = 1, SHADE_LEVELS do
      local s = AMBIENT + DIFFUSE * (i - 1) / (SHADE_LEVELS - 1)
      levels[i] = lcd.RGB(min(255, floor(rgb[1] * s)), min(255, floor(rgb[2] * s)), min(255, floor(rgb[3] * s)))
    end
    cached[mat] = levels
  end
  shadeCache[key] = cached
  return cached
end

---------------------------------------------------------------------------
-- Per-paint buffers (reused)
---------------------------------------------------------------------------

local VX, VY, VZ, SX, SY = {}, {}, {}, {}, {}
local faceDepth = {}
local faceColor = {}
local drawOrder = {}
local drawCount = 0

local function fartherFirst(a, b)
  return faceDepth[a] < faceDepth[b]
end

-- MSP_ATTITUDE degrees -> the angles rotatePoint() takes.
local function toRadians(roll, pitch, yaw)
  return rad(-(pitch or 0)), rad(-(yaw or 0)), rad(-(roll or 0))
end

-- The last paint's rotation matrix and projection, for the arrows.
local m11, m12, m13, m21, m22, m23, m31, m32, m33 = 1, 0, 0, 0, 1, 0, 0, 0, 1
local pcx, pcy, pscale = 0, 0, 1

-- A model point (renderer axes) on screen, or nil behind the camera.
local function project(x, y, z)
  local vx = x * m11 + y * m12 + z * m13
  local vy = x * m21 + y * m22 + z * m23
  local vz = x * m31 + y * m32 + z * m33
  local denom = CAMERA_DIST - vz
  if denom <= CAMERA_NEAR_EPS then return nil end
  local f = CAMERA_DIST / denom * pscale
  return pcx + vx * f, pcy - vy * f
end

local function drawModel(cx, cy, scale, pitchR, yawR, rollR, shades)
  -- Rotation matrix: the images of the three model axes, then the camera
  -- elevation (a tilt about the screen's horizontal axis).
  local ax, ay, az = rotatePoint(1, 0, 0, pitchR, yawR, rollR)
  local bx, by, bz = rotatePoint(0, 1, 0, pitchR, yawR, rollR)
  local cx3, cy3, cz3 = rotatePoint(0, 0, 1, pitchR, yawR, rollR)
  ay, az = ay * CAM_EC - az * CAM_ES, ay * CAM_ES + az * CAM_EC
  by, bz = by * CAM_EC - bz * CAM_ES, by * CAM_ES + bz * CAM_EC
  cy3, cz3 = cy3 * CAM_EC - cz3 * CAM_ES, cy3 * CAM_ES + cz3 * CAM_EC
  m11, m12, m13, m21, m22, m23, m31, m32, m33 = ax, bx, cx3, ay, by, cy3, az, bz, cz3
  pcx, pcy, pscale = cx, cy, scale

  for i = 1, vertexCount do
    local x, y, z = MX[i], MY[i], MZ[i]
    local vx = x * ax + y * bx + z * cx3
    local vy = x * ay + y * by + z * cy3
    local vz = x * az + y * bz + z * cz3
    VX[i], VY[i], VZ[i] = vx, vy, vz
    local denom = CAMERA_DIST - vz
    if denom <= CAMERA_NEAR_EPS then
      SX[i] = false
    else
      local f = CAMERA_DIST / denom * scale
      SX[i] = cx + vx * f
      SY[i] = cy - vy * f
    end
  end

  local count = 0
  for i = 1, faceCount do
    local a, b, c, d = FA[i], FB[i], FC[i], FD[i]
    if SX[a] and SX[b] and SX[c] and (d == 0 or SX[d]) then
      local x0, y0, z0 = VX[a], VY[a], VZ[a]
      local ux, uy, uz = VX[b] - x0, VY[b] - y0, VZ[b] - z0
      local wx, wy, wz = VX[c] - x0, VY[c] - y0, VZ[c] - z0
      local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
      local facing = nx * -x0 + ny * -y0 + nz * (CAMERA_DIST - z0)
      local visible = true
      if facing < 0 then
        if FTWO[i] then
          nx, ny, nz = -nx, -ny, -nz
        else
          visible = false
        end
      end
      if visible then
        local len = sqrt(nx * nx + ny * ny + nz * nz)
        local lambert = 0
        if len > 0 then
          lambert = (nx * LIGHT_X + ny * LIGHT_Y + nz * LIGHT_Z) / len
          if lambert < 0 then lambert = 0 end
        end
        count = count + 1
        drawOrder[count] = i
        if d == 0 then
          faceDepth[i] = (z0 + VZ[b] + VZ[c]) / 3
        else
          faceDepth[i] = (z0 + VZ[b] + VZ[c] + VZ[d]) * 0.25
        end
        faceColor[i] = shades[FMAT[i]][floor(lambert * (SHADE_LEVELS - 1) + 0.5) + 1]
      end
    end
  end
  for i = count + 1, drawCount do drawOrder[i] = nil end
  drawCount = count
  if count == 0 then return end

  t_sort(drawOrder, fartherFirst)
  for k = 1, count do
    local i = drawOrder[k]
    local a, b, c, d = FA[i], FB[i], FC[i], FD[i]
    lcd.color(faceColor[i])
    lcd.drawFilledTriangle(SX[a], SY[a], SX[b], SY[b], SX[c], SY[c])
    if d ~= 0 then
      lcd.drawFilledTriangle(SX[a], SY[a], SX[c], SY[c], SX[d], SY[d])
    end
  end
end

-- Arrows for pose(): from the middle of each lit surface's trailing edge,
-- the way that edge should go, in the text colour so they stand out from
-- the lit surface.
local arrowColors = {}

local function drawArrows(scale, dark)
  local any = false
  for k = 1, surfaceCount do
    if SDIR[k] then any = true break end
  end
  if not any then return end
  local key = dark and 1 or 2
  if not arrowColors[key] then arrowColors[key] = dark and lcd.RGB(245, 245, 245) or lcd.RGB(20, 20, 20) end
  lcd.color(arrowColors[key])
  local len = max(16, floor(scale * 0.7))
  local head = max(6, floor(len * 0.42))
  local half = max(1, floor(len * 0.08))
  for k = 1, surfaceCount do
    local d = SDIR[k]
    if d then
      local t1, t2 = ST1[k], ST2[k]
      local mx, my, mz = (MX[t1] + MX[t2]) * 0.5, (MY[t1] + MY[t2]) * 0.5, (MZ[t1] + MZ[t2]) * 0.5
      local s = 0.5 * d[4]
      local px, py = project(mx, my, mz)
      local qx, qy = project(mx + d[1] * s, my + d[2] * s, mz + d[3] * s)
      if px and qx then
        local ux, uy = qx - px, qy - py
        local ul = sqrt(ux * ux + uy * uy)
        -- Pointing (nearly) at the camera: no arrow to draw.
        if ul > 0.5 then
          ux, uy = ux / ul, uy / ul
          local nx, ny = -uy, ux
          local sx, sy = px + ux * 3, py + uy * 3
          local tx, ty = sx + ux * len, sy + uy * len
          local bx, by = tx - ux * head, ty - uy * head
          lcd.drawFilledTriangle(sx + nx * half, sy + ny * half, bx + nx * half, by + ny * half, bx - nx * half, by - ny * half)
          lcd.drawFilledTriangle(sx + nx * half, sy + ny * half, bx - nx * half, by - ny * half, sx - nx * half, sy - ny * half)
          local hw = head * 0.6
          lcd.drawFilledTriangle(tx, ty, bx + nx * hw, by + ny * hw, bx - nx * hw, by - ny * hw)
        end
      end
    end
  end
end

local plane3d = {}

plane3d.DEFAULT = DEFAULT_SPEC

-- Which airframe to draw (see the header); nil for the default. Rebuilds
-- the mesh only when the spec differs from the last one (by identity, then
-- by content), and leaves every surface at neutral.
function plane3d.setup(spec)
  spec = spec or DEFAULT_SPEC
  if spec == currentSpec then return end
  local c = currentSpec
  local function sameSpan(a, b)
    if a == nil or b == nil then return a == b end
    return a[1] == b[1] and a[2] == b[2]
  end
  if not (c and c.tail == spec.tail and c.wing == spec.wing and sameSpan(c.outer, spec.outer)
      and sameSpan(c.inner, spec.inner) and c.fin == spec.fin and c.rudder == spec.rudder
      and c.winglets == spec.winglets and c.gear == spec.gear) then
    build(spec)
    currentArrows = nil
  end
  currentSpec = spec
end

-- Light up and deflect the surfaces that have an arrow (see the header);
-- nil puts every surface back to neutral. Recomputes only when given a
-- different table.
function plane3d.pose(arrows)
  arrows = arrows or NO_ARROWS
  if arrows == currentArrows then return end
  currentArrows = arrows
  applyPose(arrows)
end

-- The model at (roll, pitch, yaw), fitted inside the box and clipped to it.
-- At zoom 1 (the default) the model's radius is fitted to the box's
-- shorter side, so it stays inside at any attitude; perspective can push a
-- tip pointing at the camera slightly further, which the clip catches. A
-- caller whose model only tilts a little can zoom in and let the clip take
-- the rare overflow.
function plane3d.draw(x, y, w, h, roll, pitch, yaw, zoom)
  if w < 8 or h < 8 then return end
  local pitchR, yawR, rollR = toRadians(roll, pitch, yaw)
  local scale = max(4, (min(w, h) * 0.5 - 4) / MODEL_RADIUS * (zoom or 1))
  local sw, sh = lcd.getWindowSize()
  local dark = lcd.darkMode()
  lcd.setClipping(x, y, w, h)
  drawModel(x + floor(w * 0.5), y + floor(h * 0.5), scale, pitchR, yawR, rollR, shadeTable(dark))
  drawArrows(scale, dark)
  lcd.setClipping(0, 0, sw, sh)
end

-- Where the nose points on screen, as a unit vector (x right, y up), or
-- nil when it points straight at or away from the viewer.
function plane3d.noseDirection(roll, pitch, yaw)
  local pitchR, yawR, rollR = toRadians(roll, pitch, yaw)
  local nx, ny, nz = rotatePoint(2.2, 0.0, 0.0, pitchR, yawR, rollR)
  local tx, ty, tz = rotatePoint(-2.2, 0.0, 0.0, pitchR, yawR, rollR)
  local nd, td = CAMERA_DIST - nz, CAMERA_DIST - tz
  if nd <= CAMERA_NEAR_EPS or td <= CAMERA_NEAR_EPS then return nil end
  local dx = nx * CAMERA_DIST / nd - tx * CAMERA_DIST / td
  local dy = ny * CAMERA_DIST / nd - ty * CAMERA_DIST / td
  local mag = sqrt(dx * dx + dy * dy)
  if mag <= 0.001 then return nil end
  return dx / mag, dy / mag
end

package.loaded["wfsuite.app.plane3d"] = plane3d
return plane3d
