import { useState } from "react";
import { EyeIcon, EyeOffIcon } from "./Icons";

export default function LoginTab({ onLogin }: { onLogin?: (identity: string, password: string) => Promise<string | null> }) {
  const [showPassword, setShowPassword] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  return (
    <form
      className="flex flex-col gap-5"
      onSubmit={async (e) => {
        e.preventDefault();
        setError(null);
        if (!email.trim() || !password) {
          setError('Enter your email and password to continue.');
          return;
        }
        setIsSubmitting(true);
        try {
          const message = await onLogin?.(email, password);
          if (message) setError(message);
        } catch (err) {
          console.error('Login error:', err);
          setError('Sign-in failed. Please try again.');
        } finally {
          setIsSubmitting(false);
        }
      }}
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

      {error && (
        <p role="alert" className="text-xs rounded px-3 py-2"
          style={{ background: "rgba(179,38,30,0.08)", color: "#B3261E", border: "1px solid rgba(179,38,30,0.25)" }}>
          {error}
        </p>
      )}

      <button
        type="submit"
        disabled={isSubmitting}
        className="w-full py-2.5 text-sm font-semibold transition-colors mt-1"
        style={{
          backgroundColor: isSubmitting ? "#1B3F63" : "#0E2A47",
          color: "#ffffff",
          borderRadius: "4px",
          border: "1px solid #0E2A47",
          fontFamily: "'Public Sans', sans-serif",
          cursor: isSubmitting ? "not-allowed" : "pointer",
          letterSpacing: "0.01em",
          opacity: isSubmitting ? 0.7 : 1,
        }}
      >
        {isSubmitting ? (
          <span className="flex items-center justify-center gap-2">
            <span className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
            Logging in...
          </span>
        ) : "Log In"}
      </button>

      <p
        className="text-xs text-center leading-relaxed"
        style={{ color: "#5B6472", fontFamily: "'Noto Sans', sans-serif" }}
      >
        Access is provisioned by your district administrator.
      </p>
    </form>
  );
}
