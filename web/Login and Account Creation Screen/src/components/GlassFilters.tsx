// SVG displacement filters powering the liquid-glass effect. The turbulence
// map displaces the backdrop (refraction), and per-channel displacement at
// slightly different scales produces a restrained chromatic-aberration fringe
// at the edges. Referenced via `backdrop-filter: url(#liquidGlass)`.
export default function GlassFilters() {
  return (
    <svg
      aria-hidden="true"
      width="0"
      height="0"
      style={{ position: "absolute", pointerEvents: "none" }}
    >
      <defs>
        <Filter id="liquidGlass" scaleR={13} scaleG={10} scaleB={7} freq="0.011 0.014" />
        <Filter id="liquidGlassStrong" scaleR={20} scaleG={16} scaleB={12} freq="0.013 0.016" />
      </defs>
    </svg>
  );
}

function Filter({
  id,
  scaleR,
  scaleG,
  scaleB,
  freq,
}: {
  id: string;
  scaleR: number;
  scaleG: number;
  scaleB: number;
  freq: string;
}) {
  return (
    <filter id={id} x="-20%" y="-20%" width="140%" height="140%" colorInterpolationFilters="sRGB">
      <feTurbulence
        type="fractalNoise"
        baseFrequency={freq}
        numOctaves={2}
        seed={11}
        result="turb"
      />
      <feGaussianBlur in="turb" stdDeviation="1.3" result="soft" />

      {/* Red channel — largest displacement */}
      <feDisplacementMap
        in="SourceGraphic"
        in2="soft"
        scale={scaleR}
        xChannelSelector="R"
        yChannelSelector="G"
        result="disR"
      />
      <feColorMatrix
        in="disR"
        type="matrix"
        values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0"
        result="chR"
      />

      {/* Green channel — mid displacement */}
      <feDisplacementMap
        in="SourceGraphic"
        in2="soft"
        scale={scaleG}
        xChannelSelector="R"
        yChannelSelector="G"
        result="disG"
      />
      <feColorMatrix
        in="disG"
        type="matrix"
        values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0"
        result="chG"
      />

      {/* Blue channel — smallest displacement */}
      <feDisplacementMap
        in="SourceGraphic"
        in2="soft"
        scale={scaleB}
        xChannelSelector="R"
        yChannelSelector="G"
        result="disB"
      />
      <feColorMatrix
        in="disB"
        type="matrix"
        values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0"
        result="chB"
      />

      <feBlend in="chR" in2="chG" mode="screen" result="rg" />
      <feBlend in="rg" in2="chB" mode="screen" />
    </filter>
  );
}
