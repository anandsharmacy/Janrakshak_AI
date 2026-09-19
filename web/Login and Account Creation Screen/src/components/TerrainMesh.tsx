// Faint navy-on-navy topographic contour field suggesting NER terrain,
// with a live route trace and pulsing connectivity-risk nodes.

const W = 800;
const H = 700;

// Deterministic irregular closed contour ring around a peak center.
function contour(cx: number, cy: number, r: number, seed: number): string {
  const pts = 28;
  const coords: [number, number][] = [];
  for (let i = 0; i < pts; i++) {
    const a = (i / pts) * Math.PI * 2;
    const wobble =
      1 +
      0.16 * Math.sin(a * 3 + seed) +
      0.09 * Math.sin(a * 5 + seed * 1.7) +
      0.05 * Math.cos(a * 2 + seed * 0.4);
    const rr = r * wobble;
    coords.push([cx + rr * Math.cos(a), cy + rr * Math.sin(a) * 0.72]);
  }
  // Smooth closed path via Catmull-Rom-ish quadratic midpoints.
  let d = `M ${coords[0][0].toFixed(1)} ${coords[0][1].toFixed(1)}`;
  for (let i = 0; i < pts; i++) {
    const cur = coords[i];
    const next = coords[(i + 1) % pts];
    const mx = (cur[0] + next[0]) / 2;
    const my = (cur[1] + next[1]) / 2;
    d += ` Q ${cur[0].toFixed(1)} ${cur[1].toFixed(1)} ${mx.toFixed(1)} ${my.toFixed(1)}`;
  }
  return d + " Z";
}

// Two peaks; nested rings expanding outward form the relief field.
const peaks = [
  { cx: 300, cy: 300, count: 9, base: 34, step: 40, seed: 1.2 },
  { cx: 560, cy: 460, count: 7, base: 30, step: 44, seed: 3.6 },
];

export default function TerrainMesh({
  variant = "navy",
  showGlyphs = true,
}: {
  variant?: "navy" | "bronze";
  showGlyphs?: boolean;
}) {
  const line = variant === "bronze" ? "#8A5E33" : "#0E2A47";
  const routeBase =
    variant === "bronze" ? "rgba(138,94,51,0.18)" : "rgba(14,42,71,0.16)";

  return (
    <svg
      className="pointer-events-none absolute inset-0 h-full w-full"
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid slice"
      aria-hidden="true"
    >
      {/* Contour relief */}
      <g fill="none" stroke={line} strokeWidth="1">
        {peaks.map((p, pi) =>
          Array.from({ length: p.count }).map((_, i) => (
            <path
              key={`${pi}-${i}`}
              d={contour(p.cx, p.cy, p.base + i * p.step, p.seed + i * 0.35)}
              style={{ opacity: 0.06 + (p.count - i) * 0.007 }}
            />
          )),
        )}
      </g>

      {/* Live supply route tracing the terrain */}
      <path
        id="ner-route"
        d="M 90 560 C 220 520, 250 380, 360 340 S 540 300, 610 180 S 700 110, 740 90"
        fill="none"
        stroke={routeBase}
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      {showGlyphs && (
        <>
          <path
            className="route-glow"
            d="M 90 560 C 220 520, 250 380, 360 340 S 540 300, 610 180 S 700 110, 740 90"
            fill="none"
            stroke="#C2691A"
            strokeWidth="2.25"
            strokeLinecap="round"
            strokeDasharray="46 514"
            style={{ filter: "drop-shadow(0 0 3px rgba(194,105,26,0.4))" }}
          />

          {/* Connectivity-risk nodes */}
          <RiskNode x={360} y={340} color="#C2691A" delay={0} />
          <RiskNode x={610} y={180} color="#1E6B45" delay={1.6} />
          <RiskNode x={218} y={470} color="#1E6B45" delay={3.1} />
        </>
      )}
    </svg>
  );
}

function RiskNode({
  x,
  y,
  color,
  delay,
}: {
  x: number;
  y: number;
  color: string;
  delay: number;
}) {
  return (
    <g>
      <circle
        className="risk-ping"
        cx={x}
        cy={y}
        r={4}
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        style={{ animation: `nodePing 3.2s ease-out ${delay}s infinite` }}
      />
      <circle
        className="risk-core"
        cx={x}
        cy={y}
        r={3}
        fill={color}
        style={{
          animation: `nodeCore 3.2s ease-in-out ${delay}s infinite`,
          filter: `drop-shadow(0 0 3px ${color})`,
        }}
      />
    </g>
  );
}
