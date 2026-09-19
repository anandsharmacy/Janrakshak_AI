import { useState } from "react";
import { EyeIcon, EyeOffIcon, MapPinIcon, BuildingIcon, RadarIcon, ChevronDownIcon } from "./Icons";
import { REGIONS, districtsOf, isValidLocation, statesOf } from "../data/indiaLocations";
import { profileService } from "@/lib/profileService";

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
  const [selectedRegion, setSelectedRegion] = useState("");
  const [selectedState, setSelectedState] = useState("");
  const [selectedDistrict, setSelectedDistrict] = useState("");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);

  // Field and District Officers pick Region -> State -> District; Control Room stops at State.
  const needsDistrict = selectedRole === "field-officer" || selectedRole === "district-officer";
  const canSubmit = selectedRole !== null && fullName.trim() !== "" && email.trim() !== "" &&
    isValidLocation(selectedRegion, selectedState, needsDistrict ? selectedDistrict : undefined);

  if (submitted) {
    return (
      <div className="flex flex-col items-center gap-3 text-center" style={{ fontFamily: "'Noto Sans', sans-serif" }}>
        <p className="text-sm font-semibold" style={{ color: "#1E6B45" }}>
          Account created successfully. You can now log in.
        </p>
      </div>
    );
  }

  return (
    <form
      className="flex flex-col gap-5"
      onSubmit={(e) => {
        e.preventDefault();
        if (!canSubmit || !selectedRole) return;
        const roleLabel = selectedRole === "field-officer" ? "Field Officer" : selectedRole === "district-officer" ? "District Officer" : "Control Officer";
        const regionValue = needsDistrict ? `${selectedDistrict}, ${selectedState}` : `${selectedState}, ${selectedRegion} Region`;
        const roleShort = selectedRole === "field-officer" ? "FO" : selectedRole === "district-officer" ? "DO" : "CO";
        const randomId = Math.floor(1000 + Math.random() * 9000);
        const profile = {
          profileName: fullName.trim(),
          profileInitials: fullName.trim().split(/\s+/).map((part) => part[0]).join("").slice(0, 2).toUpperCase(),
          officerId: `NER-${roleShort}-${randomId}`,
          // Not collected on the form; profiles still show a role-based default.
          department: selectedRole === "field-officer" ? "Field Operations & Incident Response" : selectedRole === "district-officer" ? "District Disaster & Logistics Management" : "Regional Command & Coordination",
          region: regionValue,
          state: selectedState,
          district: needsDistrict ? selectedDistrict : undefined,
          phone: "",
          email: email.trim(),
          label: roleLabel,
          lastLogin: "Current session",
          status: "Active",
        };
        profileService.registerAccount(profile);
        localStorage.setItem("ner-registration-email", email.trim().toLowerCase());
        setSubmitted(true);
      }}
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
          type="text"
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
                    // Control Room has no District; Region and State stay valid for every role.
                    if (id === "control-room") setSelectedDistrict("");
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

      {selectedRole !== null && (
        <>
          <SelectField
            id="region"
            label="Region"
            value={selectedRegion}
            options={REGIONS}
            placeholder="Select Region"
            onChange={(region) => {
              setSelectedRegion(region);
              setSelectedState("");
              setSelectedDistrict("");
            }}
          />

          <SelectField
            id="state"
            label="State"
            value={selectedState}
            options={statesOf(selectedRegion)}
            placeholder={selectedRegion ? "Select State" : "Select Region First"}
            disabled={!selectedRegion}
            onChange={(state) => {
              setSelectedState(state);
              setSelectedDistrict("");
            }}
          />

          {needsDistrict && (
            <SelectField
              id="district"
              label="District"
              value={selectedDistrict}
              options={districtsOf(selectedRegion, selectedState)}
              placeholder={selectedState ? "Select District" : "Select State First"}
              disabled={!selectedState}
              onChange={setSelectedDistrict}
            />
          )}
        </>
      )}

      {/* Submit */}
      <button
        type="submit"
        disabled={!canSubmit}
        className="w-full py-2.5 text-sm font-semibold transition-colors mt-1"
        style={{
          backgroundColor: canSubmit ? "#0E2A47" : "rgba(91,100,114,0.25)",
          color: canSubmit ? "#ffffff" : "#5B6472",
          borderRadius: "4px",
          border: canSubmit ? "1px solid #0E2A47" : "1px solid rgba(91,100,114,0.25)",
          fontFamily: "'Public Sans', sans-serif",
          cursor: canSubmit ? "pointer" : "not-allowed",
          letterSpacing: "0.01em",
        }}
        onMouseEnter={(e) => {
          if (canSubmit) e.currentTarget.style.backgroundColor = "#1B3F63";
        }}
        onMouseLeave={(e) => {
          if (canSubmit) e.currentTarget.style.backgroundColor = "#0E2A47";
        }}
      >
        Create Account
      </button>

      <p
        className="text-xs text-center leading-relaxed"
        style={{ color: "#5B6472", fontFamily: "'Noto Sans', sans-serif" }}
      >
        Your account will be ready to use immediately after creation.
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

function SelectField({
  id,
  label,
  value,
  options,
  placeholder,
  disabled = false,
  onChange,
}: {
  id: string;
  label: string;
  value: string;
  options: string[];
  placeholder: string;
  disabled?: boolean;
  onChange: (value: string) => void;
}) {
  return (
    <Field label={label} htmlFor={id}>
      <div className="relative">
        <select
          id={id}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          disabled={disabled}
          aria-required="true"
          className="glass-field accent-green has-toggle appearance-none"
          style={disabled ? { opacity: 0.6, cursor: "not-allowed" } : undefined}
        >
          <option value="" disabled>
            {placeholder}
          </option>
          {options.map((o) => (
            <option key={o} value={o}>
              {o}
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
