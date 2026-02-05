# Draw.io Diagrams

This directory contains editable draw.io XML files for project architecture and workflow diagrams.

## Files

1. **01-demo-overview.drawio** - High-level demo flow with AWS service icons
2. **02-system-architecture.drawio** - AWS components overview with DevOps Agent integration
3. **03-fault-injection-flow.drawio** - Fault injection and RCA investigation flow

## How to Use

### Option 1: Open in draw.io Desktop App
1. Download [draw.io Desktop](https://github.com/jgraph/drawio-desktop/releases)
2. File → Open → Select .drawio file
3. Edit and export as PNG/SVG/PDF

### Option 2: Open in draw.io Web (app.diagrams.net)
1. Go to https://app.diagrams.net/
2. File → Open from → Device
3. Select .drawio file
4. Edit online

### Option 3: Open in VS Code
1. Install [Draw.io Integration extension](https://marketplace.visualstudio.com/items?itemName=hediet.vscode-drawio)
2. Click on .drawio file to edit inline

## Export Settings (Recommended)

For PNG export:
- Zoom: 100%
- Border Width: 10px
- Transparent Background: No (use white)
- Include a copy of diagram: Yes (for re-editing)

For SVG export:
- Include a copy of diagram: Yes
- Transparent Background: Optional

## Color Palette (AWS Branding)

- **API Gateway**: `#E7157B` (pink)
- **Lambda**: `#FF9900` (orange)
- **S3**: `#569A31` (green)
- **CloudWatch/X-Ray**: `#527FFF` (blue)
- **SNS**: `#D45B07` (orange-red)
- **DevOps Agent**: `#FF4F8B` (magenta)
- **GitHub**: `#24292e` (dark gray)

## Tips

- All diagrams use consistent color coding for AWS services
- Text is editable - update service names/IDs as needed
- Resize canvas: File → Page Setup
- Export all at once: File → Export → Batch export
