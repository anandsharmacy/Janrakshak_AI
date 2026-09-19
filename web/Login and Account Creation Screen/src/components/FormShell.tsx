import { ArrowLeftIcon, ChakraMark } from "./Icons";
import TerrainMesh from "./TerrainMesh";

// Full-screen shell for the two form pages. Bronze/copper radial wash echoing
// the emblem's material — deeper bronze at the edges fading to a warm amber-
// paper tone toward the center where the form sits — with a faint bronze
// terrain echo tying all three screens together as one system.
export default function FormShell({
  onBack,
  title,
  children,
  footerLink,
}: {
  onBack: () => void;
  title: string;
  children: React.ReactNode;
  footerLink?: { label: string; action: string; onClick: () => void };
}) {
  return (
    <div
      className="relative min-h-screen w-full flex flex-col overflow-hidden"
      style={{
        background:
          "radial-gradient(ellipse 130% 110% at 50% 42%, #F4EAD8 0%, #E6CEA6 52%, #C69C5E 100%)",
      }}
    >
      {/* Faint bronze terrain echo */}
      <div className="pointer-events-none absolute inset-0 opacity-60">
        <TerrainMesh variant="bronze" showGlyphs={false} />
      </div>

      {/* Back link */}
      <div className="relative z-10 px-8 py-6">
        <button
          onClick={onBack}
          className="inline-flex items-center gap-1.5 text-sm cursor-pointer"
          style={{
            fontFamily: "'Public Sans', sans-serif",
            color: "#5B6472",
            background: "none",
            border: "none",
            outline: "none",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.color = "#0E2A47")}
          onMouseLeave={(e) => (e.currentTarget.style.color = "#5B6472")}
        >
          <ArrowLeftIcon />
          Back
        </button>
      </div>

      {/* Centered form column */}
      <div className="relative z-10 flex flex-1 items-center justify-center px-6 pb-16">
        <div className="form-card-in w-full max-w-[480px] flex flex-col gap-8">
          <div className="flex flex-col gap-2">
            {/* Persistent emblem mark — the handoff from the splash settles here */}
            <span style={{ color: "#9A6E3E" }}>
              <ChakraMark size={22} />
            </span>
            <span
              className="text-[11px] uppercase"
              style={{
                fontFamily: "'Public Sans', sans-serif",
                color: "#5B6472",
                letterSpacing: "0.16em",
              }}
            >
              Secure Sign-In
            </span>
            <h2
              className="text-xl font-semibold tracking-tight"
              style={{
                fontFamily: "'Public Sans', sans-serif",
                color: "#0E2A47",
              }}
            >
              {title}
            </h2>
          </div>

          <div className="liquid-card w-full">
            <div className="relative z-10 p-7">{children}</div>
          </div>

          {footerLink && (
            <p
              className="text-xs text-center"
              style={{ color: "#5B6472", fontFamily: "'Noto Sans', sans-serif" }}
            >
              {footerLink.label}{" "}
              <button
                onClick={footerLink.onClick}
                className="cursor-pointer underline"
                style={{
                  fontFamily: "'Public Sans', sans-serif",
                  color: "#0E2A47",
                  background: "none",
                  border: "none",
                  padding: 0,
                }}
              >
                {footerLink.action}
              </button>
            </p>
          )}

          <p
            className="text-[11px] leading-relaxed text-center"
            style={{ color: "#5B6472", fontFamily: "'Noto Sans', sans-serif" }}
          >
            For official use only. Activity on this system is monitored and
            logged. Unauthorized access is an offence under applicable law.
          </p>
        </div>
      </div>
    </div>
  );
}
