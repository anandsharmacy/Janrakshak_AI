import { useState } from "react";
import { EyeIcon, EyeOffIcon } from "./Icons";
import { supabase } from "../lib/supabase";

const OFFICER_ID_MAP: Record<string, string> = {
  "NER-FO-4471": "a.sangma@ner.gov.in",
  "NER-DO-2210": "r.borah@kamrup.gov.in",
  "NER-DO-2281": "r.borah@kamrup.gov.in",
  "NER-CR-0007": "s.khongsdier@ner.gov.in",
  "NER-CO-0012": "s.khongsdier@ner.gov.in",
  "NER-RD-1184": "p.lyngdoh@ner.gov.in",
};

function resolveEmail(input: string): string {
  const trimmed = input.trim();
  return OFFICER_ID_MAP[trimmed.toUpperCase()] ?? trimmed;
}

export default function LoginTab() {
  const [showPassword, setShowPassword] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [status, setStatus] = useState<{ type: "error" | "success"; message: string } | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const submit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setStatus(null);

    if (!email.trim() || !password) {
      setStatus({ type: "error", message: "Enter your email and password to continue." });
      return;
    }

    setSubmitting(true);
    const resolvedEmail = resolveEmail(email);
    const { error } = await supabase.auth.signInWithPassword({
      email: resolvedEmail,
      password,
    });
    setSubmitting(false);

    if (error) {
      setStatus({ type: "error", message: "The email or password is incorrect." });
      return;
    }

    setStatus({ type: "success", message: "Signed in successfully." });
  };

  return (
    <form
      className="flex flex-col gap-5"
      onSubmit={submit}
      style={{ fontFamily: "'Noto Sans', sans-serif" }}
    >
      <div className="flex flex-col gap-1.5">
        <label
          htmlFor="email"
          className="text-xs font-medium uppercase tracking-wide"
          style={{ fontFamily: "'Public Sans', sans-serif", color: "#5B6472", letterSpacing: "0.06em" }}
        >
          Email / Username
        </label>
        <input
          id="email"
          type="text"
          autoComplete="username"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="officer@gov.in or employee ID"
          className="glass-field accent-saffron"
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <div className="flex items-center justify-between">
          <label
            htmlFor="password"
            className="text-xs font-medium uppercase tracking-wide"
            style={{ fontFamily: "'Public Sans', sans-serif", color: "#5B6472", letterSpacing: "0.06em" }}
          >
            Password
          </label>
          <a
            href="#"
            className="text-xs transition-colors"
            style={{ color: "#5B6472", textDecoration: "underline" }}
            onMouseEnter={(e) => (e.currentTarget.style.color = "#0E2A47")}
            onMouseLeave={(e) => (e.currentTarget.style.color = "#5B6472")}
          >
            Forgot password?
          </a>
        </div>
        <div className="relative">
          <input
            id="password"
            type={showPassword ? "text" : "password"}
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Enter your password"
            className="glass-field accent-saffron has-toggle"
          />
          <button
            type="button"
            onClick={() => setShowPassword((v) => !v)}
            className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center justify-center"
            style={{ color: "#5B6472", background: "none", border: "none", cursor: "pointer", padding: "2px" }}
            aria-label={showPassword ? "Hide password" : "Show password"}
          >
            {showPassword ? <EyeOffIcon /> : <EyeIcon />}
          </button>
        </div>
      </div>

      <button
        type="submit"
        disabled={submitting}
        className="w-full py-2.5 text-sm font-semibold transition-colors mt-1"
        style={{
          backgroundColor: "#0E2A47",
          color: "#ffffff",
          borderRadius: "4px",
          border: "1px solid #0E2A47",
          fontFamily: "'Public Sans', sans-serif",
          cursor: submitting ? "wait" : "pointer",
          letterSpacing: "0.01em",
        }}
        onMouseEnter={(e) => {
          if (!submitting) e.currentTarget.style.backgroundColor = "#1B3F63";
        }}
        onMouseLeave={(e) => {
          if (!submitting) e.currentTarget.style.backgroundColor = "#0E2A47";
        }}
      >
        {submitting ? "Signing in..." : "Log In"}
      </button>

      {status && (
        <p
          role="status"
          className="text-xs text-center leading-relaxed"
          style={{ color: status.type === "success" ? "#1E6B45" : "#9B2C2C" }}
        >
          {status.message}
        </p>
      )}

      <p
        className="text-xs text-center leading-relaxed"
        style={{ color: "#5B6472", fontFamily: "'Noto Sans', sans-serif" }}
      >
        Access is provisioned by your district administrator.
      </p>
    </form>
  );
}
