# Mini ERP - Design System

**Version:** 2.0 Hybrid  
**Inspiration:** Supabase (dark emerald) + Professional ERP patterns  
**Last Updated:** 2026-04-09

---

## Design Philosophy

**Aesthetic:** Developer tool precision meets enterprise SaaS. Think Supabase dashboard meets Oracle NetSuite - dark, data-dense, professional.

**Core Values:**
- **Data Density** - Efficient screen real estate for business data
- **Contrast Clarity** - High contrast for readability in various lighting
- **Trust & Authority** - Professional enough for CFOs, approachable for data entry

**Mood:** Reliable, efficient, sophisticated. Not playful, not stark. Built for 8-hour work sessions.

---

## Visual Theme & Atmosphere

### Light Mode - Clean Professional

| Element | Value |
|---------|-------|
| Background | `#FAFBFC` (slightly warm white) |
| Surface | `#FFFFFF` |
| Border | `#E5E7EB` |
| Text Primary | `#111827` |
| Text Secondary | `#6B7280` |
| Accent | `#059669` (Emerald) |

### Dark Mode - Supabase Inspired

| Element | Value |
|---------|-------|
| Background | `#0A0F0D` (deep forest black) |
| Surface | `#111916` (dark emerald) |
| Surface Elevated | `#1A2820` |
| Border | `#2D3D36` |
| Text Primary | `#ECFEED` |
| Text Secondary | `#86EFAC` (emerald-100) |
| Accent | `#10B981` (Supabase emerald) |

---

## Color Palette

### Light Mode

| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| Primary | Emerald | `#059669` | CTAs, success states, primary actions |
| Primary Hover | Dark Emerald | `#047857` | Button hover, active links |
| Primary Light | Light Emerald | `#D1FAE5` | Selected rows, badges, backgrounds |
| Secondary | Slate | `#475569` | Secondary buttons, neutral actions |
| Background | Off-White | `#FAFBFC` | Page background |
| Surface | White | `#FFFFFF` | Cards, panels, inputs |
| Border | Gray | `#E5E7EB` | Dividers, card edges, input borders |
| Text Primary | Near Black | `#111827` | Headings, body text |
| Text Secondary | Gray | `#6B7280` | Labels, secondary info |
| Success | Green | `#10B981` | Completed, paid, positive |
| Warning | Amber | `#F59E0B` | Pending, attention needed |
| Error | Red | `#EF4444` | Errors, overdue, delete |

### Dark Mode

| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| Primary | Emerald | `#10B981` | CTAs, active states |
| Primary Hover | Light Emerald | `#34D399` | Button hover |
| Primary Dim | Dim Emerald | `#065F46` | Subtle highlights |
| Background | Forest Black | `#0A0F0D` | Page background |
| Surface | Dark Emerald | `#111916` | Cards, panels |
| Surface Elevated | Elevated | `#1A2820` | Modals, dropdowns |
| Border | Muted | `#2D3D36` | Dividers, borders |
| Text Primary | Mint White | `#ECFEED` | Headings, body |
| Text Secondary | Soft Green | `#86EFAC` | Labels, secondary |
| Success | Bright Green | `#34D399` | Success states |
| Warning | Golden | `#FBBF24` | Warning states |
| Error | Rose | `#FB7185` | Error states |

---

## Typography

### Font Stack

| Element | Font | Usage |
|---------|------|-------|
| Headings | Inter | H1-H6, titles |
| Body | Inter | General text |
| UI/Labels | Inter | Buttons, inputs, nav |
| Monospace | JetBrains Mono | Numbers, codes, SKUs |

### Type Scale

| Level | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| Display | 32px | 700 | 1.2 | Dashboard hero numbers |
| H1 | 24px | 600 | 1.25 | Page titles |
| H2 | 20px | 600 | 1.3 | Section headers |
| H3 | 16px | 600 | 1.4 | Card titles, table headers |
| Body | 14px | 400 | 1.5 | General text |
| Body Small | 13px | 400 | 1.5 | Secondary text, metadata |
| Caption | 12px | 500 | 1.4 | Labels, badges |
| Tiny | 11px | 500 | 1.3 | Timestamps, tooltips |

### Font Weights

| Weight | Value | Usage |
|--------|-------|-------|
| Regular | 400 | Body text |
| Medium | 500 | Emphasis, labels, buttons |
| Semibold | 600 | Headings, nav items |
| Bold | 700 | Display numbers, totals |

---

## Spacing System

### Scale (4px base)

| Token | Value | Usage |
|-------|-------|-------|
| `--space-1` | 4px | Icon margins, tight inline |
| `--space-2` | 8px | Compact element spacing |
| `--space-3` | 12px | Form field internal padding |
| `--space-4` | 16px | Standard padding, gap |
| `--space-5` | 20px | Card internal padding |
| `--space-6` | 24px | Section spacing |
| `--space-8` | 32px | Large section spacing |
| `--space-10` | 40px | Page margins |
| `--space-12` | 48px | Dashboard padding |

### Component Spacing

- **Form inputs:** 12px vertical, 16px horizontal
- **Cards:** 20px padding
- **Tables:** 10px 16px (compact 8px 12px)
- **Buttons:** 10px 16px (small: 6px 12px)
- **Modals:** 24px content, 16px actions

---

## Border Radius

| Size | Value | Usage |
|------|-------|-------|
| None | 0 | Strict inputs |
| Small | 4px | Buttons, inputs, badges |
| Medium | 6px | Cards, panels |
| Large | 8px | Modals, large cards |
| XL | 12px | Dropdowns, popovers |
| Full | 9999px | Pills, avatars |

---

## Shadows

### Light Mode

| Level | Shadow | Usage |
|-------|--------|-------|
| Subtle | `0 1px 2px rgba(0,0,0,0.05)` | Card hover |
| Card | `0 1px 3px rgba(0,0,0,0.1), 0 1px 2px rgba(0,0,0,0.06)` | Cards |
| Dropdown | `0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -1px rgba(0,0,0,0.06)` | Dropdowns |
| Modal | `0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -4px rgba(0,0,0,0.04)` | Modals |
| Focus Ring | `0 0 0 3px rgba(5,150,105,0.3)` | Input focus |

### Dark Mode

| Level | Shadow | Usage |
|-------|--------|-------|
| Subtle | `0 1px 2px rgba(0,0,0,0.3)` | Card hover |
| Card | `0 1px 3px rgba(0,0,0,0.4)` | Cards |
| Dropdown | `0 4px 6px -1px rgba(0,0,0,0.5)` | Dropdowns |
| Modal | `0 20px 25px -5px rgba(0,0,0,0.5)` | Modals |
| Focus Ring | `0 0 0 3px rgba(16,185,129,0.3)` | Input focus |

---

## Components

### Buttons

#### Primary (Emerald)
```css
/* Light Mode */
background: #059669;
color: white;
padding: 10px 16px;
border-radius: 6px;
hover: #047857;

/* Dark Mode */
background: #10B981;
color: #0A0F0D;
hover: #34D399;
```

#### Secondary
```css
/* Light Mode */
background: transparent;
border: 1px solid #E5E7EB;
color: #374151;
hover: #F9FAFB;

/* Dark Mode */
background: transparent;
border: 1px solid #2D3D36;
color: #86EFAC;
hover: #1A2820;
```

#### Ghost
```css
background: transparent;
color: #6B7280;
hover: #F3F4F6;
```

#### Danger
```css
background: #EF4444;
color: white;
hover: #DC2626;
```

#### Sizes
- Large: 14px font, 12px 20px padding
- Medium: 14px font, 10px 16px padding
- Small: 13px font, 6px 12px padding

### Inputs

```css
/* Light Mode */
background: white;
border: 1px solid #E5E7EB;
border-radius: 6px;
padding: 10px 14px;
font-size: 14px;
focus: border-color #059669 + focus ring;

/* Dark Mode */
background: #111916;
border: 1px solid #2D3D36;
color: #ECFEED;
focus: border-color #10B981 + focus ring;
```

### Cards

```css
/* Light Mode */
background: white;
border: 1px solid #E5E7EB;
border-radius: 8px;
padding: 20px;
shadow: subtle;

/* Dark Mode */
background: #111916;
border: 1px solid #2D3D36;
```

### Tables

```css
/* Light Mode */
header-bg: #F9FAFB;
header-text: #374151;
row-hover: #F9FAFB;
selected-row: #D1FAE5;
cell-padding: 10px 16px;

/* Dark Mode */
header-bg: #1A2820;
header-text: #86EFAC;
row-hover: #1A2820;
selected-row: #065F46;
```

### Badges/Pills

- Border radius: 9999px (full)
- Padding: 4px 10px
- Font: 12px, 500 weight
- Background: semantic color at 15% opacity
- Text: semantic color at 100%

### Modals

- Background: white (light) / #111916 (dark)
- Border radius: 12px
- Padding: 24px
- Shadow: Modal shadow
- Overlay: rgba(0,0,0,0.5)
- Max width: 560px (standard), 800px (large)

---

## Layout Principles

### Grid System
- 12-column grid
- Gutter: 24px (desktop), 16px (mobile)
- Margin: 24px (desktop), 16px (mobile)

### Responsive Breakpoints

| Breakpoint | Width | Layout |
|------------|-------|--------|
| Mobile | < 640px | Single column, stacked |
| Tablet | 640px - 1024px | 2-column, collapsible sidebar |
| Desktop | > 1024px | Full grid, sidebar visible |
| Wide | > 1440px | Max content 1440px |

### Sidebar
- Width: 260px (expanded), 72px (collapsed)
- Background: #F9FAFB (light) / #0A0F0D (dark)
- Border: right border

### Data Density Options

| Mode | Row Height | Use Case |
|------|------------|----------|
| Compact | 32px | Large datasets, quick scanning |
| Standard | 40px | Default, balanced |
| Comfortable | 48px | Detailed review, touch devices |

---

## Z-Index Scale

| Layer | Value | Usage |
|-------|-------|-------|
| Base | 0 | Default |
| Dropdown | 100 | Dropdowns, popovers |
| Sticky | 200 | Sticky headers |
| Fixed | 300 | Fixed actions |
| Modal | 400 | Modals, dialogs |
| Toast | 500 | Notifications |
| Tooltip | 600 | Tooltips |

---

## Do's and Don'ts

### Do
- ✅ Use emerald green as primary (distinctive, trustworthy)
- ✅ Maintain high contrast in dark mode for readability
- ✅ Provide clear focus states for accessibility
- ✅ Use data-dense tables for large datasets
- ✅ Include loading states for async operations
- ✅ Apply subtle shadows consistently
- ✅ Use semantic colors (green=success, red=error, amber=warning)

### Don't
- ❌ Mix accent colors - stick to emerald primary
- ❌ Use bright colors for backgrounds (use light variants)
- ❌ Create inconsistent button styles
- ❌ Skip error states on form inputs
- ❌ Make text too small (minimum 13px for body)
- ❌ Forget mobile-responsive layouts
- ❌ Use excessive shadows (reserve for elevated elements)

---

## Responsive Behavior

### Desktop (> 1024px)
- Full sidebar visible
- Multi-column layouts
- Horizontal tables
- All features accessible

### Tablet (640px - 1024px)
- Collapsible sidebar
- Stacked layouts for forms
- Horizontal scroll for wide tables
- Touch-friendly targets (44px min)

### Mobile (< 640px)
- Hidden sidebar (hamburger menu)
- Single column layouts
- Card-based data display
- Bottom navigation or tabs

### Touch Targets
- Minimum: 44px x 44px
- Recommended: 48px x 48px
- Button padding: minimum 12px

---

## Design Token Reference (for developers, not AI behavioral instructions)

### Quick Color Reference

```
Primary (Light): #059669
Primary (Dark): #10B981
Success: #10B981 / #34D399
Warning: #F59E0B / #FBBF24
Error: #EF4444 / #FB7185

Light: Background #FAFBFC, Surface #FFFFFF
Dark: Background #0A0F0D, Surface #111916
```

### Example Design Briefs

These are sample prompts a developer might give to an AI when generating UI components:

**"Create a data table with sorting and filtering using Mini ERP's emerald design tokens."**

**"Build a form with validation states following the Mini ERP input styles - emerald focus ring, proper error states."**

**"Design a dashboard card component with proper shadows and hover states in dark mode."**

**"Create a modal dialog with the Mini ERP modal styling - centered, with backdrop blur."**

---

## Implementation Notes

- This design system prioritizes data density and efficiency for business users
- Dark mode is first-class - designed with same attention as light mode
- All interactive elements must have visible focus states for accessibility
- Test with real business data to ensure readability at scale
- Emerald accent distinguishes this from generic blue enterprise tools
