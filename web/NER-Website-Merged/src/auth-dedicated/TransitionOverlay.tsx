import { useEffect, useState } from "react";
import EmblemMedallion from "./EmblemMedallion";

// Full-screen tricolor wipe used for splash ↔ form navigation. The gradient
// band sweeps diagonally across the viewport while the bronze emblem "hands
// off" — scaling down and arcing toward the top-left corner of the new page.
export default function TransitionOverlay({
  stage,
  dir,
}: {
  stage: "cover" | "reveal";
  dir: "forward" | "back";
}) {
  const [entered, setEntered] = useState(false);

  useEffect(() => {
    const r = requestAnimationFrame(() =>
      requestAnimationFrame(() => setEntered(true)),
    );
    return () => cancelAnimationFrame(r);
  }, []);

  const forward = dir === "forward";

  // Band position: enters from one side, exits out the other (one sweep).
  let bandX: string;
  if (stage === "reveal") bandX = forward ? "116%" : "-116%";
  else bandX = entered ? "0%" : forward ? "-116%" : "116%";

  // Emblem handoff: fades in centered, then arcs to the corner and shrinks.
  let emblem: React.CSSProperties;
  if (stage === "reveal")
    emblem = { transform: "translate(-38vw, -32vh) scale(0.22)", opacity: 0 };
  else if (entered)
    emblem = { transform: "translate(0, 0) scale(0.8)", opacity: 1 };
  else emblem = { transform: "translate(0, 0) scale(0.5)", opacity: 0 };

  return (
    <div className="fixed inset-0 z-50 overflow-hidden pointer-events-none">
      {/* Sweeping tricolor band — lighter splash palette, deliberate pace */}
      <div
        className="absolute top-0 h-full"
        style={{
          left: "-15vw",
          width: "130vw",
          transform: `translateX(${bandX}) skewX(-9deg)`,
          transition: "transform 900ms cubic-bezier(0.33, 0, 0.2, 1)",
          background:
            "linear-gradient(118deg, #E2B57F 0%, #EFE3CC 34%, #F1ECE0 50%, #DDE6D0 66%, #A7C1AC 100%)",
          boxShadow: "0 0 80px rgba(0,0,0,0.18)",
        }}
      />

      {/* Handoff emblem */}
      <div
        className="absolute left-1/2 top-1/2"
        style={{
          marginLeft: "-126px",
          marginTop: "-126px",
          transition:
            "transform 950ms cubic-bezier(0.33, 0, 0.2, 1), opacity 850ms ease-out",
          ...emblem,
        }}
      >
        <EmblemMedallion />
      </div>
    </div>
  );
}
