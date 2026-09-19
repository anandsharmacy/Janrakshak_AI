import TerrainMesh from "./TerrainMesh";
import EmblemMedallion from "./EmblemMedallion";
import { ChakraMark } from "./Icons";

// Screen 1 — full-viewport splash / landing.
export default function IdentityPanel({
  onLogin,
  onCreate,
}: {
  onLogin: () => void;
  onCreate: () => void;
}) {
  return (
    <div
      className="relative min-h-screen w-full flex flex-col overflow-hidden"
      style={{
        // Muted tricolor wash: light saffron → warm paper → light sage green.
        // Low saturation so it reads "official document", not flag poster.
        background:
          "linear-gradient(180deg, #E2B57F 0%, #EFE3CC 40%, #F1ECE0 54%, #A7C1AC 100%)",
      }}
    >
      {/* Topographic terrain of the NER region, navy-on-light */}
      <TerrainMesh />

      {/* Top: classification / system status line */}
      <div className="relative z-10 flex items-center justify-between px-10 py-8 lg:px-16">
        <span
          className="text-[11px] uppercase"
          style={{
            fontFamily: "'Public Sans', sans-serif",
            color: "rgba(14,42,71,0.6)",
            letterSpacing: "0.22em",
          }}
        >
          Restricted · Provisioned Access
        </span>
        <span className="flex items-center gap-2">
          <span
            className="inline-block h-1.5 w-1.5 rounded-full"
            style={{
              backgroundColor: "#1E6B45",
              boxShadow: "0 0 0 3px rgba(30,107,69,0.22)",
            }}
          />
          <span
            className="text-[11px] uppercase"
            style={{
              fontFamily: "'Public Sans', sans-serif",
              color: "rgba(14,42,71,0.6)",
              letterSpacing: "0.16em",
            }}
          >
            System Live
          </span>
        </span>
      </div>

      {/* Center: rotating emblem, identity, and the two entry actions */}
      <div className="splash-in relative z-10 flex flex-1 flex-col items-center justify-center gap-9 px-6 py-8">
        <EmblemMedallion />

        <div className="flex flex-col items-center gap-3 text-center">
          <h1
            className="text-[38px] leading-[1.05] font-bold tracking-tight lg:text-[46px]"
            style={{ fontFamily: "'Public Sans', sans-serif", color: "#0E2A47" }}
          >
            Janrakshak AI
          </h1>
          <p
            className="max-w-[440px] text-sm leading-relaxed"
            style={{
              fontFamily: "'Noto Sans', sans-serif",
              color: "rgba(14,42,71,0.72)",
            }}
          >
            Terrain-aware routing, connectivity risk mapping, and fleet
            coordination across the North Eastern Region.
          </p>
        </div>

        <div className="flex items-center gap-4 pt-1">
          <button
            onClick={onLogin}
            className="px-8 py-2.5 text-sm font-semibold transition-colors cursor-pointer"
            style={{
              fontFamily: "'Public Sans', sans-serif",
              backgroundColor: "#0E2A47",
              color: "#F5F5F1",
              border: "1px solid #0E2A47",
              borderRadius: "5px",
              letterSpacing: "0.01em",
            }}
            onMouseEnter={(e) =>
              (e.currentTarget.style.backgroundColor = "#1B3F63")
            }
            onMouseLeave={(e) =>
              (e.currentTarget.style.backgroundColor = "#0E2A47")
            }
          >
            Log in
          </button>
          <button
            onClick={onCreate}
            className="px-8 py-2.5 text-sm font-semibold transition-colors cursor-pointer"
            style={{
              fontFamily: "'Public Sans', sans-serif",
              backgroundColor: "transparent",
              color: "#0E2A47",
              border: "1px solid #0E2A47",
              borderRadius: "5px",
              letterSpacing: "0.01em",
            }}
            onMouseEnter={(e) =>
              (e.currentTarget.style.backgroundColor = "rgba(14,42,71,0.06)")
            }
            onMouseLeave={(e) =>
              (e.currentTarget.style.backgroundColor = "transparent")
            }
          >
            Create account
          </button>
        </div>
      </div>

      {/* Bottom: credibility line */}
      <div className="relative z-10 flex items-center justify-center gap-2.5 px-6 pb-8">
        <span style={{ color: "#0E2A47" }}>
          <ChakraMark size={16} />
        </span>
        <span
          className="text-xs text-center"
          style={{
            fontFamily: "'Noto Sans', sans-serif",
            color: "rgba(14,42,71,0.64)",
          }}
        >
          Ministry of Development of North Eastern Region · Government of India
        </span>
      </div>
    </div>
  );
}
