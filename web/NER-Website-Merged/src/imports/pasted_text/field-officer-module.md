Design a professional government-grade web application module for an **AI-Based Smart Logistics and Accessibility Intelligence Platform for the North Eastern Region (NER)**.

Create the complete **FIELD OFFICER module** while strictly maintaining visual consistency with the existing **DISTRICT OFFICER dashboard**.

IMPORTANT:
Do NOT redesign the visual language.
Do NOT introduce a new color palette.
Do NOT introduce different fonts, card styles, button styles, spacing rules, border radii, icon styles, or dashboard patterns.

The Field Officer module must look like it belongs to the EXACT SAME product and design system as the District Officer module.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. EXISTING DESIGN SYSTEM — MUST REMAIN IDENTICAL
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Use the same three primary brand colors:

• Deep Navy Blue: #17324D
• Teal: #2F6F7E
• Muted Gold: #D7A73A

Use the same neutral colors:

• Page Background: #F5F7F9
• Card / Surface: #FFFFFF
• Secondary Surface: #EEF2F5
• Border: #D8E0E6
• Primary Text: #17212B
• Secondary Text: #5F6B76
• Muted Text: #87929C

Semantic operational colors:

• Green = Safe / Resolved
• Amber = Moderate / Warning
• Orange = High Risk
• Red = Critical / Emergency
• Blue = Information

Never use colors as the only indicator.
Always combine status colors with icons, labels, badges, or text.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2. TYPOGRAPHY — EXACTLY MATCH DISTRICT OFFICER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Use **Inter** throughout the application.

Maintain the same typography scale:

• Page Title: 28px, Semibold
• Section Heading: 20px, Semibold
• Card Heading: 16px, Semibold
• Body Text: 14px
• Table Text: 13–14px
• Metadata: 12px
• KPI Numbers: 28–32px, Bold
• Button Text: 14px, Medium
• Navigation Text: 14px

Do not randomly change font sizes between pages.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
3. GLOBAL LAYOUT — SAME AS DISTRICT OFFICER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Desktop-first responsive government operations interface.

Layout:

• Left sidebar: approximately 240–260px
• Top header
• Main content area
• Page padding: 24px
• Card spacing: 16–24px
• Section spacing: 24–32px
• Card radius: 10–12px
• Button radius: 6–8px
• Thin subtle borders
• Very light shadows
• Clean white surfaces
• No excessive gradients
• No glassmorphism
• No unnecessary decorative elements

Keep the same sidebar structure, header structure, logo placement, profile treatment, notification icon, and general navigation behavior as the District Officer dashboard.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
4. FIELD OFFICER NAVIGATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create the following sidebar navigation:

FIELD OFFICER

• Dashboard
• My Tasks
• Report Incident
├── Road Blockage
├── Flood
├── Landslide
├── Accident
├── Infrastructure Damage
└── Other
• Route Status
• Logistics
• Alerts
• Reports
• Profile

Use consistent line-style icons matching the District Officer icon system.

Suggested icons:

Dashboard → LayoutDashboard
My Tasks → ClipboardCheck
Report Incident → TriangleAlert / PlusCircle
Road Blockage → Construction
Flood → Waves
Landslide → Mountain
Accident → Car / CarFront
Infrastructure Damage → Building2
Other → CircleHelp
Route Status → Route
Logistics → Truck
Alerts → Bell
Reports → FileText
Profile → UserCircle

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
5. FIELD OFFICER DASHBOARD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design the Field Officer dashboard as a **field operations dashboard**.

The dashboard should answer:

• What tasks do I have?
• What incidents are near me?
• What routes require attention?
• Are there active alerts?
• What logistics movement is affected?
• What do I need to report?
• What should I do next?

Top header:

• Page title: "Field Officer Dashboard"
• Officer name
• Current district / assigned area
• Online / Offline status
• Notification icon
• Profile menu

First section:

Create compact KPI cards:

• Assigned Tasks
• Pending Tasks
• Active Incidents
• Critical Alerts

Use the same KPI card design as District Officer.

Example:

Assigned Tasks
08

Pending
03

Active Incidents
05

Critical Alerts
02

Second section:

Create a large **Current Area Situation** card.

Show:

• Current assigned area
• Route accessibility score
• Current weather condition
• Active incidents nearby
• Risk level
• Last updated time

Example:

AREA STATUS
Dimapur District

Accessibility Score
72 / 100

Risk Level
HIGH

Nearby Incidents
04

Last Updated
2 min ago

Use a small visual risk indicator.

Third section:

Create **My Priority Tasks**.

Show task cards containing:

• Task ID
• Task title
• Location
• Priority
• Due time
• Status
• Action button

Example:

TASK #FO-1024
Inspect flooded road

Location:
Dimapur–Kohima Route

Priority:
Critical

Due:
Today, 4:30 PM

Status:
Pending

Button:
"Start Task"

Fourth section:

Create **Nearby Incidents**.

Show a compact list or map/list hybrid:

• Incident type
• Distance
• Location
• Severity
• Time reported
• Status

Example:

Flood
2.4 km away
NH-29
Critical
12 min ago

Road Blockage
5.1 km away
Local Route 04
High
28 min ago

Include:
"View All Incidents"

Fifth section:

Create **Quick Actions**.

Large, highly accessible actions:

• Report Flood
• Report Road Blockage
• Report Landslide
• Report Accident
• Report Infrastructure Damage

Use consistent buttons/cards and icons.

The "Report Incident" action should be visually prominent because this is a primary Field Officer operation.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
6. MY TASKS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create a task management page.

Tabs:

• All
• Pending
• In Progress
• Completed
• Overdue

Task table/cards:

Task ID
Task
Location
Priority
Assigned Time
Due Time
Status
Action

Allow:

• Start Task
• View Details
• Update Status
• Complete Task

Task status flow:

Assigned
→ Accepted
→ In Progress
→ Completed
→ Verified

Use subtle transitions when task status changes.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
7. REPORT INCIDENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This is one of the MOST IMPORTANT Field Officer workflows.

Create a simple step-by-step incident reporting experience.

Step indicator:

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

Incident types:

• Road Blockage
• Flood
• Landslide
• Accident
• Infrastructure Damage
• Other

Keep the form simple because the Field Officer may be using a mobile device under difficult field conditions.

Location section:

• Auto-detect GPS
• Latitude / Longitude
• Location name
• Route name
• Nearby landmark

Evidence section:

• Capture / Upload Image
• Upload multiple images
• Add short video if available
• Timestamp
• GPS metadata

Details:

• Severity
• Description
• Road condition
• Accessibility
• Vehicles affected
• Estimated blockage
• Immediate action required

AI-generated section:

After evidence and details are entered, show:

AI INCIDENT ASSESSMENT

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

Clearly label these as **AI-generated estimates**, not guaranteed facts.

Final review page:

Show a clean summary before submission.

Button:
"Submit Incident"

After submission:

Show confirmation:

Incident Reported Successfully

Incident ID:
INC-2026-XXXX

Status:
Under Review

Notify District Officer:
Sent

Do not immediately disappear to another page.
Show a short confirmation state and then allow:

"View Incident"
"Back to Dashboard"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
8. ROUTE STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create a route monitoring page.

Show:

• Route name
• Accessibility Score
• Risk Level
• Current Condition
• Active Incident
• Weather Impact
• Last Updated

Example:

NH-29
Accessibility: 72
Risk: HIGH
Condition: Partially Accessible

Use the same Dynamic Accessibility Score visual style as District Officer.

Allow Field Officer to open route details.

Route detail should show:

• Route map
• Current accessibility score
• Active incidents
• Weather conditions
• Flood risk
• Landslide risk
• Road condition
• Recent history
• Recommended action

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
9. LOGISTICS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create a logistics monitoring page focused on shipments/vehicles relevant to the Field Officer.

Show:

• Vehicle ID
• Shipment ID
• Origin
• Destination
• Current location
• Route
• Status
• Risk
• ETA

Example statuses:

On Route
Delayed
At Risk
Stopped
Delivered

Field Officer should be able to open a logistics movement and see:

• Vehicle location
• Assigned route
• Route accessibility
• Nearby incidents
• Expected delay
• Risk level
• Latest update

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
10. ALERTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create an alerts page.

Categories:

• Critical
• High
• Moderate
• Information

Each alert should contain:

• Alert type
• Location
• Time
• Severity
• Description
• Recommended action

Critical alerts should have strong visual hierarchy but remain professional.

Example:

CRITICAL ALERT

Flood reported near NH-29

2.4 km from your assigned location

Recommended Action:
Avoid affected section and inspect alternate access route.

Buttons:

"View Incident"
"Mark as Acknowledged"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
11. REPORTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create a simple Field Officer reports page.

Show:

• Incident reports submitted
• Tasks completed
• Route inspections
• Logistics observations
• Daily activity report

Allow:

• View
• Download
• Generate Report

Create a clean report preview rather than a complicated analytics dashboard.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
12. PROFILE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create a professional officer profile page.

Show:

• Officer name
• Officer ID
• Designation
• Assigned district
• Assigned area
• Contact information
• Current availability
• Last synchronization
• Device / connectivity status

Include:

Notification Preferences
Offline Data
Security
Logout

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
13. OFFLINE FIELD MODE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Because Field Officers may work in areas with poor connectivity, design an **Offline Mode**.

Header should clearly indicate:

● Online

or

● Offline — Data will sync automatically

When offline:

• Allow incident reports to be created
• Store reports locally
• Allow task updates
• Allow evidence capture
• Queue synchronization

When connectivity returns:

Show:

"Syncing field data..."

Then:

"All field data synced"

Use a subtle animated sync icon.

Do NOT make offline mode visually alarming.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
14. TRANSITIONS & MICRO-INTERACTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IMPORTANT:

Add professional, subtle transitions throughout the application while maintaining the government operations aesthetic.

Animations must be functional, not decorative.

Use:

• 150–200ms hover transitions
• 200–300ms page/card transitions
• Subtle sidebar active-state animation
• Smooth tab switching
• Smooth modal opening
• Smooth dropdown transitions
• Button press feedback
• Progress indicator animation
• Skeleton loading states
• Toast notifications
• Status change transitions

Loading states:

Use skeleton loaders for:

• KPI cards
• Incident lists
• Task lists
• Route information
• Logistics tables
• Dashboard maps

Do NOT use a generic spinning circle everywhere.

For synchronization:

Use a small animated sync icon.

Example:

↻ Syncing field data...

Then:

✓ Data synchronized

For AI analysis:

When generating an AI risk assessment, show a short professional processing state:

"Analyzing incident conditions..."

Use a subtle animated AI/status icon or progress indicator.

Then transition into:

Risk Assessment
HIGH

Confidence
89%

Avoid flashy AI animations.

For map loading:

Show map skeleton / loading placeholder before the map becomes interactive.

For incident submission:

Button changes:

"Submit Incident"
→
"Submitting..."
→
"Incident Reported ✓"

For task completion:

"Complete Task"
→
"Updating..."
→
"Task Completed ✓"

For alert acknowledgement:

"Acknowledge"
→
"Acknowledged ✓"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
15. PAGE TRANSITIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Use subtle page transitions.

When navigating:

Dashboard → My Tasks
Dashboard → Report Incident
Dashboard → Route Status
Dashboard → Logistics
Dashboard → Alerts

Use a short fade/slide transition.

Do not use dramatic page animations.

The application should feel like a professional government command-and-field system.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
16. RESPONSIVE DESIGN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Field Officers may primarily use phones/tablets in the field.

Create responsive layouts for:

Desktop
Tablet
Mobile

On mobile:

• Sidebar becomes a drawer
• KPI cards become 2-column or single-column
• Tables become stacked cards
• Maps become full-width
• Report Incident becomes optimized for touch
• Primary actions become large touch-friendly buttons
• Bottom navigation may be used if appropriate

Minimum touch target:
44px.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
17. DESIGN CONSISTENCY RULE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ABSOLUTELY NO visual drift from the District Officer dashboard.

Reuse:

• Same color tokens
• Same typography tokens
• Same spacing
• Same card components
• Same button components
• Same badges
• Same table components
• Same modal style
• Same sidebar
• Same header
• Same icon style
• Same map style
• Same status indicators
• Same accessibility rules

Only change the information architecture and content required for the Field Officer role.

District Officer =
District-level monitoring and decision making.

Field Officer =
Ground-level operations, tasks, reporting, inspection and evidence collection.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
18. FIGMA COMPONENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create reusable components:

• Sidebar
• Header
• KPI Card
• Task Card
• Incident Card
• Status Badge
• Risk Badge
• Priority Badge
• Alert Card
• Route Card
• Logistics Card
• Evidence Upload
• Stepper
• Form Field
• Map Container
• AI Insight Card
• Accessibility Score
• Loading Skeleton
• Toast Notification
• Confirmation Modal
• Offline Indicator
• Sync Indicator
• Empty State

Create variants for:

Default
Hover
Active
Disabled
Loading
Success
Warning
Critical

Use Auto Layout and reusable components wherever possible.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
19. VISUAL STYLE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Overall feeling:

Government
Professional
Reliable
Operational
Clean
Trustworthy
Field-ready
Data-driven
Calm under pressure

Avoid:

• Startup-style gradients
• Neon colors
• Excessive glass effects
• Huge decorative illustrations
• Gaming-style dashboards
• Excessive rounded cards
• Excessive animations
• Unnecessary 3D graphics

The interface should look suitable for actual government logistics and emergency-response operations.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
20. FIELD OFFICER DEMO FLOW
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Create the complete prototype flow:

Field Officer Dashboard
↓
Receives Critical Alert
↓
Opens Incident
↓
Travels / Inspects Location
↓
Report Incident
↓
Selects Flood
↓
GPS Location Captured
↓
Uploads Evidence
↓
Adds Incident Details
↓
AI Generates Risk Estimate
↓
Reviews Incident
↓
Submits Incident
↓
District Officer Receives Alert
↓
Field Officer sees:
"Incident submitted successfully"
↓
Incident status:
Under Review
↓
Field Officer returns to Dashboard
↓
Task appears:
"Monitor affected route"
↓
Task status:
In Progress
↓
Task Completed
↓
District Officer verifies resolution

Make this flow clickable and prototype-ready.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINAL REQUIREMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The Field Officer module must feel like the **same product as the District Officer dashboard**.

Maintain EXACT consistency in:

COLOR
FONT
FONT SIZE
SPACING
CARDS
BUTTONS
ICONS
BORDERS
RADIUS
SHADOWS
STATUS COLORS
MAP STYLE
TABLE STYLE
NAVIGATION
HEADER
COMPONENTS
ANIMATIONS
TRANSITIONS

Only the role-specific content and workflows should change.

Prioritize usability, readability, operational clarity, accessibility, and realistic government field operations over visual decoration.
