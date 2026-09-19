Design a complete professional **District Officer Operations Portal** for an **AI-Based Smart Logistics and Accessibility Intelligence Platform for the North Eastern Region (NER)**.

This is a government operations and intelligence platform, NOT a generic SaaS dashboard.

The District Officer is responsible for monitoring a district, verifying field reports, managing incidents, monitoring routes and logistics, coordinating field officers, reviewing AI insights, handling alerts, and generating operational reports.

Create the following complete District Officer module:

DISTRICT OFFICER
├── Dashboard
├── District Map
├── Incidents
│   ├── All
│   ├── Pending Verification
│   ├── Active
│   ├── Escalated
│   └── Resolved
├── Routes
├── Logistics
├── Field Officers
├── Tasks
├── AI Insights
├── Alerts
├── Reports
└── Analytics

==================================================

1. OVERALL VISUAL DIRECTION
   ==================================================

Create a professional government-grade operational interface.

The visual style should communicate:

* Government operations
* Geospatial intelligence
* Logistics monitoring
* Emergency response
* Reliability
* Data-driven decision making
* AI-assisted intelligence

Avoid:

* Generic SaaS appearance
* Startup landing-page aesthetics
* Excessive gradients
* Glassmorphism
* Neon colors
* Gaming-style interfaces
* Excessively rounded cards
* Decorative illustrations
* Unnecessary animations

The interface should look realistic enough that it could be used as a prototype for a government district control room.

==================================================
2. TRI-COLOR DESIGN SYSTEM
==========================

Use exactly THREE primary brand colors throughout the District Officer module.

PRIMARY COLOR:
Deep Navy Blue
#17324D

Use for:

* Sidebar
* Main navigation
* Primary buttons
* Selected navigation states
* Important headings
* Map controls
* Primary actions

SECONDARY COLOR:
Teal
#2F6F7E

Use for:

* Secondary buttons
* Selected filters
* Data highlights
* Route information
* Logistics information
* Charts
* Informational elements

ACCENT COLOR:
Muted Gold
#D7A73A

Use sparingly for:

* Important highlights
* AI insight indicators
* Key statistics
* Priority information
* Selected important data points

The three colors must remain consistent throughout every page.

Do NOT introduce additional brand colors.

Use neutral colors only for backgrounds, surfaces, borders and typography.

NEUTRALS:

Background:
#F5F7F9

Surface:
#FFFFFF

Secondary Surface:
#EEF2F5

Border:
#D8E0E6

Primary Text:
#17212B

Secondary Text:
#5F6B76

Muted Text:
#87929C

==================================================
3. SEMANTIC STATUS COLORS
=========================

Semantic colors must NOT replace the three brand colors.

Use them only for operational status.

SAFE:
Green

MODERATE:
Amber

HIGH:
Orange

CRITICAL:
Red

INFORMATION:
Blue

Always show status using:
ICON + TEXT + COLOR

Never communicate status through color alone.

Examples:

✓ SAFE
▲ MODERATE
◆ HIGH
! CRITICAL

==================================================
4. TYPOGRAPHY
=============

Use Inter.

Typography hierarchy:

Page title:
28px / Semibold

Section title:
20px / Semibold

Card title:
16px / Semibold

Body:
14px / Regular

Table:
13–14px

Metadata:
12px

KPI:
28–32px / Bold

Keep typography highly readable and professional.

Do not use decorative fonts.

==================================================
5. LAYOUT
=========

Use a desktop-first government operations dashboard.

Primary layout:

LEFT SIDEBAR
+
TOP HEADER
+
MAIN CONTENT

Sidebar width:
240–260px

Main content:
Flexible

Page padding:
24px

Card gap:
16–24px

Section spacing:
24–32px

Cards:
10–12px radius

Buttons:
6–8px radius

Use subtle borders and very light shadows.

The interface must be responsive for tablet and smaller screens.

==================================================
6. GLOBAL DISTRICT OFFICER SHELL
================================

Create a reusable application shell.

LEFT SIDEBAR:

District Officer

Dashboard
District Map
Incidents
Routes
Logistics
Field Officers
Tasks
AI Insights
Alerts
Reports
Analytics

At the bottom:

Help & Support
Profile
Logout

TOP HEADER:

Breadcrumb

District name

Global search

Date/time

Notification bell

District Officer profile

Online system status

==================================================
7. DISTRICT OFFICER DASHBOARD
=============================

Create the main District Officer dashboard.

Above the fold:

Header:

"District Operations"

Subtitle:

"Real-time district connectivity, logistics and incident intelligence"

KPI CARDS:

Active Incidents
24

Blocked Routes
07

High-Risk Routes
12

Active Logistics
86

Pending Reports
18

Average Response Time
42 min

Each KPI card should contain:

* Icon
* Large number
* Label
* Small trend/change indicator
* Optional comparison with previous period

Do not overdecorate the cards.

MAIN CONTENT:

LEFT / CENTER:
Large district map

RIGHT:
Critical alerts panel

BOTTOM:

Incident queue

Logistics overview

AI insights

==================================================
8. DISTRICT MAP
===============

Create a dedicated full-page District Map.

The map is the primary component.

Show:

* District boundary
* Major roads
* Blocked roads
* Risk zones
* Flood zones
* Landslide locations
* Active incidents
* Logistics vehicles
* Critical infrastructure
* Alternative routes

Map controls:

Search location
Zoom
Current location
Layers
Filters
Legend

Layer selector:

ROADS
INCIDENTS
FLOOD RISK
LANDSLIDE RISK
LOGISTICS
RISK
INFRASTRUCTURE

Filtering:

Risk:
Low
Moderate
High
Critical

Incident:
Flood
Landslide
Road Blockage
Accident
Infrastructure Damage
Vehicle Breakdown

Time:

Last 1 hour
Last 6 hours
Last 24 hours
Last 7 days

When a route is selected, open a side information panel.

Example:

ROUTE NH-X

Accessibility:
38 / 100

Risk:
HIGH

Current Status:
Restricted

Estimated Delay:
46 min

Weather:
Heavy rainfall

Flood Risk:
High

Landslide Risk:
Moderate

AI Recommendation:
Alternative Route B

==================================================
9. INCIDENTS MODULE
===================

Create a complete incident management system.

Main navigation:

Incidents

Tabs:

All
Pending Verification
Active
Escalated
Resolved

Use a professional data table.

Columns:

Incident ID
Type
Location
Severity
Reported By
Reported Time
Verification
Assigned Officer
Status
Actions

Example rows:

INC-2026-041
Flood
Route NH-X
Critical
FO-102
10:32 AM
Pending
—
Under Review

INC-2026-042
Landslide
Route X-Y
High
FO-118
09:48 AM
Verified
FO-121
Active

==================================================
10. INCIDENT DETAIL PAGE
========================

When the District Officer selects an incident, show a detailed incident page/drawer.

Header:

Incident ID
Severity
Current status

Sections:

INCIDENT INFORMATION

Type
Location
Reported time
Reported by
GPS coordinates
Description

EVIDENCE

Photo
Video
Timestamp
GPS information

MAP

Show exact incident location.

IMPACT

Affected route
Affected logistics
Nearby incidents
Estimated disruption

AI RISK

Risk score:
82 / 100

Risk level:
HIGH

Explain:

Heavy rainfall
Previous flooding
Road condition
Water level

ACTIONS:

Verify Incident
Assign Officer
Create Task
Escalate
Update Status
Resolve Incident

==================================================
11. PENDING VERIFICATION
========================

Create a dedicated verification queue.

Prioritize incidents requiring District Officer attention.

Each row/card should show:

Incident
Severity
Evidence availability
Reported by
Time
Location
Verification status

Actions:

View Evidence
Verify
Reject
Request More Information

Critical incidents should be visually prioritized.

==================================================
12. ACTIVE INCIDENTS
====================

Show all verified incidents currently requiring response.

Include:

Incident
Severity
Location
Assigned Officer
Response status
Elapsed time
SLA / deadline

Use a response timeline.

Example:

Reported
↓
Verified
↓
Assigned
↓
Response in Progress
↓
Resolved

==================================================
13. ESCALATED INCIDENTS
=======================

Show incidents that require higher-level attention.

Include:

Incident ID
Reason for escalation
Severity
District impact
Time unresolved
Assigned team
Escalation level

Use a strong but restrained critical visual treatment.

Include:

"Escalated to Control Officer"

==================================================
14. RESOLVED INCIDENTS
======================

Show historical resolved incidents.

Columns:

Incident
Type
Location
Reported
Resolved
Response Time
Resolved By
Impact

Include filters:

Date
Incident Type
Severity
Location

Allow opening a resolution summary.

==================================================
15. ROUTES MODULE
=================

Create a Route Intelligence page.

Show a table/list of important district routes.

Columns:

Route ID
Route Name
Distance
Accessibility
Risk
Status
Weather
ETA
Expected Delay
Last Updated

Example:

NH-X
Corridor A
120 km
38 / 100
HIGH
Restricted
Heavy Rain
4h 20m
+46 min

Add route detail view.

Route detail:

Accessibility Score
Risk Score
Weather
Flood Risk
Landslide Risk
Road Condition
Traffic
Current incidents
Historical disruption

Alternative route comparison:

CURRENT ROUTE

Distance:
120 km

ETA:
4h 20m

Risk:
82

ALTERNATIVE ROUTE

Distance:
145 km

ETA:
4h 47m

Risk:
31

AI RECOMMENDATION:

"Alternative Route B recommended due to lower disruption risk."

==================================================
16. LOGISTICS MODULE
====================

Create a dedicated district logistics monitoring screen.

Top KPIs:

Active Vehicles
Delayed Vehicles
At-Risk Shipments
Completed Movements

Main map:

Display logistics vehicles moving across routes.

Vehicle markers should show:

Vehicle ID
Cargo
Destination
Risk

Logistics table:

Vehicle ID
Cargo
Origin
Destination
Current Location
Route
ETA
Delay
Risk
Status

Example:

LG-102
Medical Supplies
Guwahati
District X
Route NH-X
4:40 PM
+46 min
HIGH
Delayed

Clicking a vehicle opens:

Vehicle details
Route
Cargo
Current location
ETA
Risk
Route recommendation

==================================================
17. FIELD OFFICERS MODULE
=========================

Create a Field Officer management page.

Show:

Total Field Officers
Available
On Task
Offline
Emergency Response

Table:

Officer ID
Name
Current Location
Current Task
Status
Last Update
Response Time

Use a map alongside the table.

Map markers:

Available
On Task
Emergency
Offline

Click an officer to see:

Current assignment
Task history
Location
Last update
Assigned incidents

==================================================
18. TASKS MODULE
================

Create a task management system.

Views:

All
New
In Progress
Completed
Escalated

Task cards/table:

Task ID
Task
Location
Priority
Assigned Officer
Created
Deadline
Status

Actions:

Assign
Reassign
View
Escalate
Complete

Task detail should contain:

Description
Location
Incident
Assigned officer
Deadline
Evidence
Progress timeline

==================================================
19. AI INSIGHTS MODULE
======================

Create a dedicated AI Intelligence page.

IMPORTANT:

Never represent predictions as guaranteed facts.

Use labels:

"AI-generated estimate"

"Prediction"

"Recommendation"

"Confidence"

Main sections:

RISK PREDICTIONS

Example:

Route NH-X

Disruption probability:
78%

Expected window:
Next 6 hours

Confidence:
78%

Contributing factors:

Heavy rainfall
Previous flood history
Poor road condition
Rising water level

LOGISTICS PREDICTION

"3 logistics routes may experience delays."

Show:

Route
Probability
Estimated delay
Main cause

ROUTE RECOMMENDATION

Show recommended alternative routes.

RESOURCE RECOMMENDATION

Example:

"2 high-priority incidents may require additional field teams."

==================================================
20. ALERTS MODULE
=================

Create an operational notification center.

Alert categories:

Critical
Route Closure
Flood
Landslide
Logistics Delay
Task
Escalation
AI Warning

Each alert:

Severity
Title
Location
Time
Description
Source
Action

Actions:

View
Acknowledge
Assign
Escalate

Critical alerts should remain visually prominent.

==================================================
21. REPORTS MODULE
==================

Create a professional report generation interface.

Report types:

Daily Situation Report
District Logistics Report
Route Risk Report
Incident Report
Disruption Report
AI Risk Report

Report generation controls:

Date
District
Incident type
Route
Severity

Preview should contain:

Report title
Date
District
KPIs
Incident summary
Route status
Logistics status
Risk overview
AI recommendations
Map
Footer

Include:

Generate Report
Export PDF
Export CSV

==================================================
22. ANALYTICS MODULE
====================

Create a decision-focused analytics dashboard.

Do not fill the page with charts.

Include:

INCIDENT TREND

Line chart:
Incidents over time

ROUTE ACCESSIBILITY

Bar chart:
Accessible vs Restricted routes

LOGISTICS DELAYS

Bar/line chart:
Average delay by route

RESPONSE TIME

Trend:
Average response time

RISK TREND

Risk score over time

DISTRICT PERFORMANCE

Compare:

Incidents
Response time
Route accessibility
Logistics delays
Unresolved incidents

Charts must support decisions rather than decoration.

==================================================
23. AI ACCESSIBILITY SCORE
==========================

Use a unified route accessibility score throughout the product.

Score:

0–25:
GOOD

26–50:
MODERATE

51–75:
RESTRICTED

76–100:
CRITICAL

Example:

ROUTE ACCESSIBILITY

38 / 100

RESTRICTED

Factors:

Road condition
Rainfall
Flood risk
Landslide risk
Traffic
Active incidents

Show this score consistently on:

Dashboard
District Map
Routes
Logistics
AI Insights
Reports

==================================================
24. INCIDENT PRIORITY
=====================

Automatically prioritize incidents.

CRITICAL:
Immediate action

HIGH:
Action required

MEDIUM:
Monitor

LOW:
Routine

Display both:

Severity badge
+
Priority label

Do not rely on color alone.

==================================================
25. WHAT-IF SIMULATION
======================

Add a simulation feature to the District Map or AI Insights.

Button:

"Simulate Route Closure"

When clicked:

Select Route

Then display:

Affected locations
Affected logistics
Estimated delays
Alternative routes
Risk changes
Required field teams

Example:

ROUTE CLOSURE SIMULATION

Route:
NH-X

Affected districts:
3

Logistics movements:
17

Estimated additional delay:
1h 24m

Alternative routes:
2

Recommended response:
Deploy 2 field teams

==================================================
26. DESIGN COMPONENTS
=====================

Create reusable components:

* Sidebar
* Header
* Breadcrumb
* KPI Card
* Map Panel
* Map Marker
* Risk Badge
* Status Badge
* Incident Card
* Incident Table
* Route Card
* Logistics Card
* Officer Card
* Task Card
* Alert Card
* AI Recommendation Card
* Filter Bar
* Search
* Date Picker
* Tabs
* Dropdown
* Modal
* Drawer
* Timeline
* Progress Indicator
* Chart Card
* Empty State
* Loading State
* Error State
* Confirmation Dialog

==================================================
27. RESPONSIVE DESIGN
=====================

Desktop:

Full sidebar
Large map
Multi-column dashboard
Dense tables

Tablet:

Collapsible sidebar
Two-column layout
Scrollable tables

Mobile:

Bottom navigation or compact sidebar
Stacked cards
Large touch targets
Simplified map controls

The District Officer experience should remain usable on laptop, tablet and mobile.

==================================================
28. ACCESSIBILITY
=================

Ensure:

High contrast
Keyboard navigation
Visible focus states
Readable typography
Accessible form labels
Large click targets
Icons + text
Color-independent status indicators
Screen-reader-friendly labels

Do not use red/green alone to communicate information.

==================================================
29. DEMO DATA
=============

Create realistic DEMO data for the North Eastern Region.

States represented:

Assam
Arunachal Pradesh
Manipur
Meghalaya
Mizoram
Nagaland
Tripura
Sikkim

Create fictional but realistic prototype data for:

Districts
Routes
Incidents
Vehicles
Field officers
Tasks
Risk scores
Alerts

Clearly mark prototype information as:

DEMO DATA

Never present fictional information as actual government data.

==================================================
30. MAIN DISTRICT OFFICER DEMO SCENARIO
=======================================

The complete module must support this workflow:

1. Field Officer reports flooding.

2. Incident appears under:
   Pending Verification.

3. District Officer opens the incident.

4. Reviews:
   GPS
   Photo
   Timestamp
   Description.

5. District Officer verifies incident.

6. Incident moves to:
   Active.

7. District Officer assigns a Field Officer.

8. System updates route accessibility.

9. Logistics vehicles using the route are identified.

10. AI generates a disruption estimate.

11. AI recommends an alternative route.

12. District Officer creates a response task.

13. Field Officer receives task.

14. Incident response begins.

15. District Officer monitors progress.

16. If unresolved beyond threshold, incident becomes:
    Escalated.

17. Control Officer is notified.

18. Incident is eventually resolved.

19. Dashboard KPIs update automatically.

This workflow should feel like ONE connected operational system.

==================================================
31. FIGMA FILE ORGANIZATION
===========================

Organize the Figma design into pages:

01 — Design System
02 — Components
03 — District Dashboard
04 — District Map
05 — Incidents
06 — Routes
07 — Logistics
08 — Field Officers
09 — Tasks
10 — AI Insights
11 — Alerts
12 — Reports
13 — Analytics
14 — Prototype Flow

Create reusable components and variants rather than drawing every screen independently.

==================================================
32. FINAL DESIGN REQUIREMENT
============================

The final District Officer module must feel like:

Government-grade
Professional
Geospatial
Operational
AI-assisted
Logistics-focused
NER-specific
Data-driven
Reliable
Accessible

It should NOT feel like:

Generic SaaS
Generic AI dashboard
College CRUD project
Random colorful dashboard
Marketing website

Most importantly, every page must feel like part of the SAME platform.

The District Officer should always be able to answer:

1. What is happening in my district?
2. Where is it happening?
3. How serious is it?
4. Which routes are affected?
5. Which logistics movements are affected?
6. Which field officers are available?
7. What should I do next?
8. What does the AI predict?
9. What needs to be escalated?

Design the interface around these questions.
