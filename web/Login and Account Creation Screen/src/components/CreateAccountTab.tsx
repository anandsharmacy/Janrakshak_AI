import { useState } from "react";
import { EyeIcon, EyeOffIcon, MapPinIcon, BuildingIcon, RadarIcon, ChevronDownIcon } from "./Icons";
import { supabase } from "../lib/supabase";
import { NER_STATE_DISTRICTS, NER_STATES } from "../data/nerStateDistricts";

type Role = "field-officer" | "district-officer" | "control-room" | null;

const ROLES: {
  id: Role;
  label: string;
  descriptor: string;
  Icon: React.FC;
}[] = [
  {
    id: "field-officer",
    label: "Field Officer",
    descriptor: "Ground reporting, route planning, incident logging.",
    Icon: MapPinIcon,
  },
  {
    id: "district-officer",
    label: "District Officer",
    descriptor: "District-level connectivity oversight and reporting review.",
    Icon: BuildingIcon,
  },
  {
    id: "control-room",
    label: "Control Room",
    descriptor: "Region-wide monitoring, fleet tracking, alert broadcast.",
    Icon: RadarIcon,
  },
];

export default function CreateAccountTab() {
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [selectedRole, setSelectedRole] = useState<Role>(null);
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [selectedState, setSelectedState] = useState("");
  const [selectedDistrict, setSelectedDistrict] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [status, setStatus] = useState<{ type: "error" | "success"; message: string } | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const isOfficer = selectedRole === "field-officer" || selectedRole === "district-officer";
  const canSubmit = selectedRole !== null &&
    (!isOfficer || (selectedState !== "" && selectedDistrict !== ""));

  const submit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setStatus(null);

    if (!fullName.trim() || !email.trim() || !password || !confirmPassword || !selectedRole) {
      setStatus({ type: "error", message: "Complete all fields and select a role to continue." });
      return;
    }
    if (isOfficer && (!selectedState || !selectedDistrict)) {
      setStatus({ type: "error", message: "Please select both State and District to continue." });
      return;
    }
    if (password.length < 8) {
      setStatus({ type: "error", message: "Password must be at least 8 characters." });
      return;
    }
    if (password !== confirmPassword) {
      setStatus({ type: "error", message: "Passwords do not match." });
      return;
    }

    setSubmitting(true);
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: {
        data: {
          full_name: fullName.trim(),
          ...(isOfficer ? { state: selectedState, district: selectedDistrict } : {}),
          requested_role: selectedRole,
        },
      },
    });
    setSubmitting(false);

    if (error) {
      setStatus({ type: "error", message: error.message });
      return;
    }

    setStatus({
      type: "success",
      message: data.session
        ? "Account created successfully."
        : "Account created. Check your email to verify it before signing in.",
    });
  };

  return (
    <form
      className="flex flex-col gap-5"
      onSubmit={submit}
      style={{ fontFamily: "'Noto Sans', sans-serif" }}
    >
      {/* Full Name */}
      <Field label="Full Name" htmlFor="full-name">
        <input
          id="full-name"
          type="text"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          placeholder="As per official records"
          className="glass-field accent-green"
        />
      </Field>

      {/* Official Email / Employee ID */}
      <Field label="Official Email / Employee ID" htmlFor="official-email">
        <input
          id="official-email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="officer@gov.in or employee ID"
          className="glass-field accent-green"
        />
      </Field>

      {/* Password */}
      <Field label="Password" htmlFor="new-password">
        <div className="relative">
          <input
            id="new-password"
            type={showPassword ? "text" : "password"}
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Minimum 8 characters"
            className="glass-field accent-green has-toggle"
          />
          <PasswordToggle show={showPassword} onToggle={() => setShowPassword((v) => !v)} label="new password" />
        </div>
      </Field>

      {/* Confirm Password */}
      <Field label="Confirm Password" htmlFor="confirm-password">
        <div className="relative">
          <input
            id="confirm-password"
            type={showConfirm ? "text" : "password"}
            autoComplete="new-password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            placeholder="Re-enter password"
            className="glass-field accent-green has-toggle"
          />
          <PasswordToggle show={showConfirm} onToggle={() => setShowConfirm((v) => !v)} label="confirm password" />
        </div>
      </Field>

      {/* Role Selection */}
      <fieldset className="flex flex-col gap-2" style={{ border: "none", padding: 0, margin: 0 }}>
        <legend
          className="text-xs font-medium uppercase tracking-wide mb-1"
          style={{ fontFamily: "'Public Sans', sans-serif", color: "#5B6472", letterSpacing: "0.06em" }}
        >
          Select Your Role
        </legend>
        {ROLES.map(({ id, label, descriptor, Icon }) => {
          const active = selectedRole === id;
          return (
            <label
              key={id}
              className={`flex items-start gap-3 px-3 py-3 cursor-pointer transition-colors ${
                active ? "" : "glass-field"
              }`}
              style={{
                border: active
                  ? "1px solid #1E6B45"
                  : "1px solid rgba(91,100,114,0.3)",
                borderRadius: "4px",
                // Selected: solid green-tinted panel. Unselected: glass.
                backgroundColor: active ? "#E9F1EC" : undefined,
                padding: "12px",
                width: "100%",
              }}
            >
              {/* Radio */}
              <div className="flex-shrink-0 mt-0.5">
                <input
                  type="radio"
                  name="role"
                  value={id!}
                  checked={active}
                  onChange={() => {
                    setSelectedRole(id);
                    if (id === "control-room") {
                      setSelectedState("");
                      setSelectedDistrict("");
                    }
                  }}
                  className="sr-only"
                />
                <div
                  className="w-4 h-4 rounded-full border-2 flex items-center justify-center"
                  style={{
                    borderColor: active ? "#1E6B45" : "rgba(91,100,114,0.5)",
                  }}
                >
                  {active && (
                    <div
                      className="w-2 h-2 rounded-full"
                      style={{ backgroundColor: "#1E6B45" }}
                    />
                  )}
                </div>
              </div>

              {/* Icon */}
              <div
                className="flex-shrink-0 mt-0.5"
                style={{ color: active ? "#1E6B45" : "#5B6472" }}
              >
                <Icon />
              </div>

              {/* Text */}
              <div className="flex flex-col gap-0.5">
                <span
                  className="text-sm font-medium"
                  style={{
                    fontFamily: "'Public Sans', sans-serif",
                    color: "#0E2A47",
                  }}
                >
                  {label}
                </span>
                <span
                  className="text-xs leading-relaxed"
                  style={{ color: "#5B6472", fontFamily: "'Noto Sans', sans-serif" }}
                >
                  {descriptor}
                </span>
              </div>
            </label>
          );
        })}
      </fieldset>

      {/* Dynamic State and District fields for Field Officer and District Officer */}
      {isOfficer && (
        <>
          {/* State */}
          <Field label="State" htmlFor="state">
            <div className="relative">
              <select
                id="state"
                value={selectedState}
                onChange={(e) => {
                  setSelectedState(e.target.value);
                  setSelectedDistrict("");
                }}
                className="glass-field accent-green has-toggle appearance-none"
              >
                <option value="" disabled>
                  Select State
                </option>
                {NER_STATES.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
              <span
                className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none"
                style={{ color: "#5B6472" }}
              >
                <ChevronDownIcon />
              </span>
            </div>
          </Field>

          {/* District */}
          <Field label="District" htmlFor="district">
            <div className="relative">
              <select
                id="district"
                value={selectedDistrict}
                onChange={(e) => setSelectedDistrict(e.target.value)}
                disabled={!selectedState}
                className="glass-field accent-green has-toggle appearance-none"
                style={!selectedState ? { opacity: 0.6, cursor: "not-allowed" } : undefined}
              >
                <option value="" disabled>
                  {selectedState ? "Select District" : "Select State First"}
                </option>
                {selectedState &&
                  (NER_STATE_DISTRICTS[selectedState] || []).map((d) => (
                    <option key={d} value={d}>
                      {d}
                    </option>
                  ))}
              </select>
              <span
                className="absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none"
                style={{ color: "#5B6472" }}
              >
                <ChevronDownIcon />
              </span>
            </div>
          </Field>
        </>
      )}

      {/* Submit */}
      <button
        type="submit"
        disabled={!canSubmit || submitting}
        className="w-full py-2.5 text-sm font-semibold transition-colors mt-1"
        style={{
          backgroundColor: canSubmit ? "#0E2A47" : "rgba(91,100,114,0.25)",
          color: canSubmit ? "#ffffff" : "#5B6472",
          borderRadius: "4px",
          border: canSubmit ? "1px solid #0E2A47" : "1px solid rgba(91,100,114,0.25)",
          fontFamily: "'Public Sans', sans-serif",
          cursor: canSubmit && !submitting ? "pointer" : "not-allowed",
          letterSpacing: "0.01em",
        }}
        onMouseEnter={(e) => {
          if (canSubmit && !submitting) e.currentTarget.style.backgroundColor = "#1B3F63";
        }}
        onMouseLeave={(e) => {
          if (canSubmit && !submitting) e.currentTarget.style.backgroundColor = "#0E2A47";
        }}
      >
        {submitting ? "Creating account..." : "Create Account"}
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
        Accounts can be created and used immediately after registration.
        <br />
        Verify your email to continue.
      </p>
    </form>
  );
}
          cursor: canSubmit && !submitting ? "pointer" : "not-allowed",
          letterSpacing: "0.01em",
        }}
        onMouseEnter={(e) => {
          if (canSubmit && !submitting) e.currentTarget.style.backgroundColor = "#1B3F63";
        }}
        onMouseLeave={(e) => {
          if (canSubmit && !submitting) e.currentTarget.style.backgroundColor = "#0E2A47";
        }}
      >
        {submitting ? "Creating account..." : "Create Account"}
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
        Accounts can be created and used immediately after registration.
        <br />
        Verify your email to continue.
      </p>
    </form>
  );
}

function Field({
  label,
  htmlFor,
  children,
}: {
  label: string;
  htmlFor: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <label
        htmlFor={htmlFor}
        className="text-xs font-medium uppercase tracking-wide"
        style={{ fontFamily: "'Public Sans', sans-serif", color: "#5B6472", letterSpacing: "0.06em" }}
      >
        {label}
      </label>
      {children}
    </div>
  );
}

function PasswordToggle({
  show,
  onToggle,
  label,
}: {
  show: boolean;
  onToggle: () => void;
  label: string;
}) {
  return (
    <button
      type="button"
      onClick={onToggle}
      className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center justify-center"
      style={{ color: "#5B6472", background: "none", border: "none", cursor: "pointer", padding: "2px" }}
      aria-label={show ? `Hide ${label}` : `Show ${label}`}
    >
      {show ? <EyeOffIcon /> : <EyeIcon />}
    </button>
  );
}
