# Microsoft 365 Admin TUI - Themes

This directory contains the CSS stylesheets for the M365 Admin TUI application.

## Files

### `app.tcss`
Main application styles including:
- Screen layout and containers
- Header section styling
- Menu and button styles with focus indicators
- Output terminal section
- Status classes (ready, running, success, error)

### `dialogs.tcss`
Modal dialog styles including:
- Base modal screen layout
- Dialog container and borders
- Form fields (labels, inputs, hints)
- Button rows and actions

## Textual CSS Variables

The stylesheets use Textual's built-in design tokens for consistent theming:

### Color Variables
- `$background` - Base background color
- `$surface` - Surface/container background
- `$surface-lighten-1`, `$surface-lighten-2` - Lighter surface variants
- `$panel` - Panel background (used for output terminal)
- `$primary` - Primary accent color
- `$secondary` - Secondary accent color
- `$accent` - Highlight/accent color
- `$text` - Primary text color
- `$text-muted` - Dimmed text color
- `$warning` - Warning state color
- `$error` - Error state color
- `$success` - Success state color

### Usage
These CSS files are automatically loaded by the application via the `CSS_PATH` property in `M365AdminApp`.

## Theme Switching

The application supports switching between Textual's built-in themes:
- **textual-dark** (default) - Dark mode theme
- **textual-light** - Light mode theme

Press `d` in the application to toggle between themes.

## Customization

To customize the appearance:
1. Edit the `.tcss` files in this directory
2. Use Textual's design tokens (variables starting with `$`)
3. The changes will be applied when the application starts

For more information on Textual CSS, see: https://textual.textualize.io/guide/CSS/
