// Embossed government-seal medallion: a matte bronze coin bearing the
// Ashoka Chakra, floating over a soft cast shadow with gentle parallax.
// Depth comes from directional lighting and material shading, not glow.

export default function EmblemMedallion() {
  const spokes = Array.from({ length: 24 }).map((_, i) => {
    const a = (i * 15 * Math.PI) / 180;
    return (
      <line
        key={i}
        x1={100 + 16 * Math.cos(a)}
        y1={100 + 16 * Math.sin(a)}
        x2={100 + 74 * Math.cos(a)}
        y2={100 + 74 * Math.sin(a)}
      />
    );
  });

  return (
    <div className="relative flex items-center justify-center">
      {/* Cast shadow on a faint pedestal */}
      <div
        className="emblem-cast absolute left-1/2 -bottom-6 h-6 w-[210px] rounded-[50%]"
        style={{
          background:
            "radial-gradient(ellipse at center, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0) 70%)",
          filter: "blur(2px)",
        }}
      />

      <div className="emblem-scene">
        <div
          className="emblem-coin relative h-[252px] w-[252px] rounded-full"
          style={{
            background:
              "radial-gradient(circle at 34% 26%, #E7BC86 0%, #C79155 24%, #9A6E3E 48%, #5E4A32 74%, #33291D 100%)",
            boxShadow:
              "inset 0 3px 4px rgba(255,240,220,0.45), inset 0 -10px 20px rgba(0,0,0,0.55), inset 0 0 0 1px rgba(0,0,0,0.25), 0 26px 40px -12px rgba(0,0,0,0.6)",
          }}
        >
          {/* Raised rim ring */}
          <div
            className="absolute inset-[14px] rounded-full"
            style={{
              boxShadow:
                "inset 0 2px 3px rgba(0,0,0,0.55), inset 0 -2px 2px rgba(255,235,205,0.35)",
              border: "1px solid rgba(255,225,180,0.18)",
            }}
          />

          {/* Recessed field */}
          <div
            className="absolute inset-[30px] rounded-full"
            style={{
              background:
                "radial-gradient(circle at 40% 34%, #B98A52 0%, #8A6438 46%, #4A3924 100%)",
              boxShadow: "inset 0 6px 12px rgba(0,0,0,0.5)",
            }}
          />

          {/* Embossed chakra */}
          <svg
            className="absolute inset-0 h-full w-full"
            viewBox="0 0 200 200"
            fill="none"
            style={{ filter: "drop-shadow(0 1.5px 0.5px rgba(0,0,0,0.55))" }}
          >
            <g
              stroke="#F0D4A6"
              strokeWidth="2"
              strokeLinecap="round"
              opacity="0.92"
            >
              <circle cx="100" cy="100" r="76" strokeWidth="2.5" />
              <circle cx="100" cy="100" r="16" strokeWidth="2.5" />
              {spokes}
            </g>
            <circle cx="100" cy="100" r="6" fill="#F0D4A6" />
            {/* Directional specular sheen, top-left */}
            <ellipse
              cx="74"
              cy="70"
              rx="52"
              ry="40"
              fill="url(#sheen)"
              opacity="0.5"
            />
            <defs>
              <radialGradient id="sheen" cx="50%" cy="50%" r="50%">
                <stop offset="0%" stopColor="#FFF4E2" stopOpacity="0.7" />
                <stop offset="100%" stopColor="#FFF4E2" stopOpacity="0" />
              </radialGradient>
            </defs>
          </svg>
        </div>
      </div>
    </div>
  );
}
