import { useEffect, useState } from "react";
import LoginTab from "./components/LoginTab";
import CreateAccountTab from "./components/CreateAccountTab";
import IdentityPanel from "./components/IdentityPanel";
import FormShell from "./components/FormShell";
import TransitionOverlay from "./components/TransitionOverlay";
import GlassFilters from "./components/GlassFilters";

type Screen = "splash" | "login" | "create";
type Dir = "forward" | "back";
type Transition = { to: Screen; dir: Dir; stage: "cover" | "reveal" };

const prefersReduced =
  typeof window !== "undefined" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export default function App() {
  const [screen, setScreen] = useState<Screen>("splash");
  const [trans, setTrans] = useState<Transition | null>(null);

  // Animated navigation for splash ↔ form only.
  const navigate = (to: Screen, dir: Dir) => {
    if (trans) return;
    if (prefersReduced) {
      setScreen(to);
      return;
    }
    setTrans({ to, dir, stage: "cover" });
  };

  // Plain swap for form ↔ form cross-links (no wipe).
  const swap = (to: Screen) => {
    if (trans) return;
    setScreen(to);
  };

  useEffect(() => {
    if (!trans) return;
    if (trans.stage === "cover") {
      const t = setTimeout(() => {
        setScreen(trans.to);
        setTrans((tr) => (tr ? { ...tr, stage: "reveal" } : null));
      }, 850);
      return () => clearTimeout(t);
    }
    const t = setTimeout(() => setTrans(null), 950);
    return () => clearTimeout(t);
  }, [trans]);

  return (
    <>
      <div key={screen}>
        {screen === "login" && (
          <FormShell
            onBack={() => navigate("splash", "back")}
            title="Access your workspace"
            footerLink={{
              label: "Don't have access?",
              action: "Create an account",
              onClick: () => swap("create"),
            }}
          >
            <LoginTab />
          </FormShell>
        )}

        {screen === "create" && (
          <FormShell
            onBack={() => navigate("splash", "back")}
            title="Request platform access"
            footerLink={{
              label: "Already have access?",
              action: "Log in",
              onClick: () => swap("login"),
            }}
          >
            <CreateAccountTab />
          </FormShell>
        )}

        {screen === "splash" && (
          <IdentityPanel
            onLogin={() => navigate("login", "forward")}
            onCreate={() => navigate("create", "forward")}
          />
        )}
      </div>

      {trans && <TransitionOverlay stage={trans.stage} dir={trans.dir} />}
      <GlassFilters />
    </>
  );
}
