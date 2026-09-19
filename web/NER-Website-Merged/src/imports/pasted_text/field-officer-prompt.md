Create a **NEW WEBSITE PAGE for the FIELD OFFICER module** of the existing project:

**AI-Based Smart Logistics and Accessibility Intelligence Platform for North Eastern Region (NER)**

IMPORTANT: This is an existing project with an already-designed **District Officer Dashboard**.

Create the Field Officer page as a **new page/screen in the same Figma project**.

### CRITICAL DESIGN RULE

**DO NOT CHANGE THE EXISTING DESIGN SYSTEM.**

The Field Officer page must look like it was designed as part of the **EXACT SAME WEBSITE** as the District Officer dashboard.

Reuse the existing District Officer:

* Color palette
* Fonts
* Font sizes
* Typography hierarchy
* Sidebar
* Header
* Icons
* Card design
* Buttons
* Tables
* Badges
* Borders
* Border radius
* Shadows
* Spacing
* Grid
* Map style
* Status indicators
* Form components
* Modal components
* Loading states
* Animations
* Transitions
* Responsive behavior

Do NOT create a new visual style.

Do NOT change the colors.

Do NOT change the font.

Do NOT change the spacing system.

Do NOT create a different sidebar.

Do NOT create a different header.

The Field Officer module should be a **role-specific extension of the existing District Officer interface**.

---

# FIELD OFFICER PAGE STRUCTURE

Create these pages/screens:

FIELD OFFICER

1. Dashboard
2. My Tasks
3. Report Incident

   * Road Blockage
   * Flood
   * Landslide
   * Accident
   * Infrastructure Damage
   * Other
4. Route Status
5. Logistics
6. Alerts
7. Reports
8. Profile

---

# 1. FIELD OFFICER DASHBOARD

Create a professional field operations dashboard.

The dashboard should prioritize:

* Current tasks
* Nearby incidents
* Route conditions
* Critical alerts
* Logistics disruptions
* Field reporting
* AI risk information

Header:

**Field Officer Dashboard**

Show:

* Field Officer name
* Assigned district / area
* Online / Offline status
* Notification icon
* Profile

Use the **EXACT SAME header design from District Officer**.

### KPI CARDS

Use the same KPI card component already used in District Officer.

Cards:

**Assigned Tasks**
08

**Pending Tasks**
03

**Active Incidents**
05

**Critical Alerts**
02

### CURRENT AREA SITUATION

Create a large card:

**Current Area Situation**

District:
Dimapur

Accessibility Score:
72 / 100

Risk Level:
HIGH

Nearby Incidents:
04

Last Updated:
2 min ago

Use the existing accessibility score and risk visualization style.

### MY PRIORITY TASKS

Show task cards:

Task ID
Task
Location
Priority
Due Time
Status

Example:

**TASK #FO-1024**

Inspect flooded road

Dimapur–Kohima Route

Priority:
Critical

Due:
Today, 4:30 PM

Status:
Pending

Button:
**Start Task**

### NEARBY INCIDENTS

Show:

Flood
2.4 km away
NH-29
Critical

Road Blockage
5.1 km away
Local Route 04
High

Button:

**View All Incidents**

### QUICK ACTIONS

Create quick-action cards using the existing component style:

* Report Flood
* Report Road Blockage
* Report Landslide
* Report Accident
* Report Infrastructure Damage

---

# 2. MY TASKS

Create a Field Officer task-management page.

Tabs:

* All
* Pending
* In Progress
* Completed
* Overdue

Use the same table/card system as the existing District Officer design.

Columns:

Task ID
Task
Location
Priority
Assigned Time
Due Time
Status
Action

Actions:

* Start Task
* View Details
* Update Status
* Complete Task

Task lifecycle:

Assigned
→ Accepted
→ In Progress
→ Completed
→ Verified

Use subtle transitions when status changes.

---

# 3. REPORT INCIDENT

This is the primary Field Officer workflow.

Create a clean, easy-to-use incident reporting page.

Use the existing design system.

### STEP INDICATOR

01 Incident Type
→
02 Location
→
03 Evidence
→
04 Details
→
05 Review
→
06 Submit

### INCIDENT TYPES

Create selectable cards:

**Road Blockage**

**Flood**

**Landslide**

**Accident**

**Infrastructure Damage**

**Other**

Use the same icon style already used throughout the project.

### LOCATION

Fields:

* Auto-detect GPS
* Latitude
* Longitude
* Location Name
* Route Name
* Nearby Landmark

Show a map using the existing map style.

### EVIDENCE

Allow:

* Capture / Upload Image
* Multiple Images
* Short Video
* Timestamp
* GPS metadata

### INCIDENT DETAILS

Fields:

* Severity
* Description
* Road Condition
* Accessibility
* Vehicles Affected
* Estimated Blockage
* Immediate Action Required

### AI INCIDENT ASSESSMENT

After the officer enters the information, show:

**AI Incident Assessment**

Risk Level:
HIGH

Incident Priority:
82 / 100

Confidence:
89%

Affected Route:
NH-29

Potential Logistics Impact:
HIGH

Clearly label AI outputs as:

**AI-generated estimate**

Do not present AI predictions as guaranteed facts.

### REVIEW

Show all submitted information in a clean summary.

Primary button:

**Submit Incident**

After clicking:

Submit Incident
→ Submitting...
→ Incident Reported ✓

Then show:

**Incident Reported Successfully**

Incident ID:
INC-2026-XXXX

Status:
Under Review

District Officer Notification:
Sent

Buttons:

**View Incident**

**Back to Dashboard**

---

# 4. ROUTE STATUS

Create a route monitoring page.

Show:

Route Name
Accessibility Score
Risk Level
Current Condition
Active Incident
Weather Impact
Last Updated

Example:

**NH-29**

Accessibility:
72 / 100

Risk:
HIGH

Condition:
Partially Accessible

Clicking a route opens:

* Route map
* Accessibility score
* Active incidents
* Weather
* Flood risk
* Landslide risk
* Road condition
* Recent history
* Recommended action

---

# 5. LOGISTICS

Create a Field Officer logistics monitoring page.

Show:

Vehicle ID
Shipment ID
Origin
Destination
Current Location
Route
Status
Risk
ETA

Statuses:

* On Route
* Delayed
* At Risk
* Stopped
* Delivered

Opening a logistics item should show:

* Vehicle location
* Assigned route
* Route accessibility
* Nearby incidents
* Expected delay
* Risk level
* Latest update

---

# 6. ALERTS

Create an alerts page.

Tabs:

* Critical
* High
* Moderate
* Information

Alert card:

**CRITICAL ALERT**

Flood reported near NH-29

2.4 km from your assigned location

Recommended Action:

Avoid affected section and inspect alternate access route.

Actions:

**View Incident**

**Acknowledge**

Acknowledge transition:

Acknowledge
→ Acknowledging...
→ Acknowledged ✓

---

# 7. REPORTS

Create a Field Officer reports page.

Show:

* Incident Reports
* Completed Tasks
* Route Inspections
* Logistics Observations
* Daily Activity Reports

Actions:

* View
* Download
* Generate Report

Keep this page simple and operational.

Do not turn it into a complex analytics dashboard.

---

# 8. PROFILE

Create a professional Field Officer profile page.

Show:

* Officer Name
* Officer ID
* Designation
* Assigned District
* Assigned Area
* Contact Information
* Availability
* Last Synchronization
* Device / Connectivity Status

Sections:

* Notification Preferences
* Offline Data
* Security
* Logout

---

# OFFLINE FIELD MODE

Field Officers may work in areas with poor connectivity.

Add an existing-system-style connectivity indicator:

**● Online**

or

**● Offline — Data will sync automatically**

When offline:

* Incident reports can still be created
* Evidence can still be captured
* Tasks can still be updated
* Data is queued for synchronization

When connection returns:

**↻ Syncing field data...**

Then:

**✓ All field data synced**

Use the same icon, animation and visual language as the rest of the website.

---

# ANIMATIONS AND TRANSITIONS

Add subtle professional interactions wherever appropriate.

Do NOT introduce flashy animations.

Use the same animation language throughout the existing website.

Use:

* 150–200ms hover transitions
* 200–300ms page transitions
* Smooth sidebar active-state transition
* Smooth tab transitions
* Modal fade/slide
* Dropdown transitions
* Button press feedback
* Toast notifications
* Skeleton loading
* Progress indicators
* Status transitions

### LOADING STATES

Use skeleton loaders instead of a generic spinner wherever possible.

For:

* KPI cards
* Tasks
* Incidents
* Routes
* Logistics
* Dashboard data
* Maps

### AI LOADING

When AI analyzes an incident:

**Analyzing incident conditions...**

Show a subtle animated AI/status icon.

Then transition to:

Risk Level:
HIGH

Confidence:
89%

Keep the animation professional and minimal.

### MAP LOADING

Show a map skeleton/loading state before the map becomes interactive.

### INCIDENT SUBMISSION

Submit Incident
→
Submitting...
→
Incident Reported ✓

### TASK COMPLETION

Complete Task
→
Updating...
→
Task Completed ✓

---

# RESPONSIVE DESIGN

The Field Officer interface must work on:

* Desktop
* Tablet
* Mobile

Field Officers may use the system while physically inspecting locations.

On mobile:

* Existing sidebar becomes a drawer
* KPI cards become responsive
* Tables become cards
* Maps become full-width
* Incident reporting becomes touch-friendly
* Primary actions become large touch targets

Minimum touch target:

**44px**

Maintain the exact same responsive behavior pattern used by the District Officer design.

---

# ICON SYSTEM

Use the same icon family/style already used in the District Officer dashboard.

Suggested semantic icons:

Dashboard → LayoutDashboard
My Tasks → ClipboardCheck
Report Incident → TriangleAlert / PlusCircle
Road Blockage → Construction
Flood → Waves
Landslide → Mountain
Accident → Car
Infrastructure Damage → Building2
Other → CircleHelp
Route Status → Route
Logistics → Truck
Alerts → Bell
Reports → FileText
Profile → UserCircle

If the existing District Officer design already uses different icons, **reuse those existing icons instead**.

---

# COMPONENT REUSE

Do not create duplicate components if equivalent components already exist.

Reuse existing:

* Sidebar
* Header
* KPI Card
* Buttons
* Cards
* Tables
* Badges
* Inputs
* Tabs
* Modals
* Alerts
* Map containers
* Status indicators
* Loading skeletons
* Toasts
* AI cards

Create variants only where the Field Officer workflow requires them.

---

# FIELD OFFICER ROLE DIFFERENCE

Keep the visual system identical but change the information priorities.

**DISTRICT OFFICER**

District-level monitoring
+
Incident verification
+
Resource management
+
Decision making
+
District analytics

**FIELD OFFICER**

Ground-level operations
+
Task execution
+
Incident reporting
+
Evidence collection
+
Route inspection
+
Local logistics monitoring

Do not make the Field Officer dashboard look like a smaller District Officer dashboard.

It should be a **field-operations interface using the same design system**.

---

# COMPLETE PROTOTYPE FLOW

Make the prototype clickable.

Flow:

Field Officer Dashboard
↓
Critical Alert
↓
Open Incident
↓
Report Incident
↓
Select Flood
↓
Capture GPS
↓
Upload Evidence
↓
Add Details
↓
AI Risk Assessment
↓
Review
↓
Submit Incident
↓
Incident Reported Successfully
↓
District Officer Notification Sent
↓
Back to Dashboard
↓
New Task Appears
↓
Start Task
↓
In Progress
↓
Complete Task
↓
Task Completed

All transitions should be smooth and consistent.

---

# FINAL NON-NEGOTIABLE REQUIREMENT

This is a **NEW FIELD OFFICER PAGE**, but it must visually belong to the **EXISTING DISTRICT OFFICER DESIGN SYSTEM**.

DO NOT change:

**Colors**
**Fonts**
**Font sizes**
**Typography**
**Spacing**
**Cards**
**Buttons**
**Icons**
**Sidebar**
**Header**
**Borders**
**Radius**
**Shadows**
**Tables**
**Maps**
**Badges**
**Status colors**
**Components**
**Animations**
**Transitions**
**Responsive behavior**

Only change the **role-specific content, navigation items, workflows, and information hierarchy** required for the Field Officer.

The final result should look like:

**One government platform → multiple roles → one consistent design system.**
