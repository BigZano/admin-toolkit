"""
SysAdmin TUI - Terminal-style interface for system administration tasks
Runs PowerShell scripts organized by category via a keyboard-driven TUI
"""

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical, ScrollableContainer
from textual.widgets import Static, Label, Input, ListView, ListItem, Footer, Button
from textual.screen import ModalScreen
from textual.binding import Binding
from textual import work, on
from pathlib import Path
import asyncio
import sys

sys.path.insert(0, str(Path(__file__).parent / "lib"))

from lib.logger import get_logger, setup_logging
from lib.config import Config
from lib.script_registry import ScriptRegistry, ScriptInfo

config = Config()
log_file = setup_logging(config.logs_dir)
logger = get_logger(__name__)


# ============================================================================
# PARAMETER INPUT MODAL
# ============================================================================

class ParameterInputModal(ModalScreen):
    """Enhanced modal for parameter input with validation"""

    CSS = """
    ParameterInputModal {
        align: center middle;
        background: $background 85%;
    }

    #param-dialog {
        width: auto;
        min-width: 60;
        max-width: 90%;
        height: auto;
        max-height: 90%;
        border: thick #ff6b35;
        background: #0f1a14;
        padding: 1 2;
    }

    #param-title {
        color: #ffb627;
        text-style: bold;
        text-align: center;
        padding: 1;
        border-bottom: solid #ff6b35;
        margin-bottom: 1;
    }

    .param-input-group {
        margin: 1 0;
        height: auto;
    }

    .param-label {
        color: #2d8659;
        text-style: bold;
        margin-bottom: 0;
    }

    .param-hint {
        color: #7a8a7f;
        text-style: italic;
        margin-bottom: 0;
    }

    .param-required {
        color: #d93a2b;
        text-style: bold;
    }

    ParameterInputModal Input {
        width: 100%;
        margin-bottom: 1;
    }

    #param-buttons {
        margin-top: 2;
        height: auto;
        align: center middle;
    }
    """

    def __init__(self, script_name: str, parameters: list, existing_values: dict = None):
        super().__init__()
        self.script_name = script_name
        self.parameters = parameters
        self.existing_values = existing_values or {}
        self.input_widgets = {}

    def compose(self) -> ComposeResult:
        with Container(id="param-dialog"):
            yield Static(f"Parameters: {self.script_name}", id="param-title")

            with ScrollableContainer():
                for param in self.parameters:
                    with Container(classes="param-input-group"):
                        label_text = param.prompt or param.name
                        if param.required:
                            label_text += " *"
                        yield Static(label_text, classes="param-label")

                        if param.default:
                            yield Static(f"Default: {param.default}", classes="param-hint")

                        input_widget = Input(
                            placeholder=param.default or "Enter value...",
                            password=param.password,
                            id=f"input-{param.name}"
                        )

                        if param.name in self.existing_values:
                            input_widget.value = self.existing_values[param.name]
                        elif param.default:
                            input_widget.value = param.default

                        self.input_widgets[param.name] = input_widget
                        yield input_widget

            if any(p.required for p in self.parameters):
                yield Static("* Required fields", classes="param-required")

            with Container(id="param-buttons"):
                yield Button("Execute", variant="primary", id="execute-btn")
                yield Button("Cancel", variant="default", id="cancel-btn")

    def on_mount(self) -> None:
        if self.input_widgets:
            list(self.input_widgets.values())[0].focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "execute-btn":
            values = {}
            missing_required = []

            for param in self.parameters:
                input_widget = self.input_widgets[param.name]
                value = input_widget.value.strip()

                if not value and param.default:
                    value = param.default

                if not value and param.required:
                    missing_required.append(param.prompt or param.name)

                if value:
                    values[param.name] = value

            if missing_required:
                self.app.notify(
                    f"Missing required: {', '.join(missing_required)}",
                    severity="error",
                    timeout=5
                )
                return

            self.dismiss({"action": "execute", "values": values})
        else:
            self.dismiss({"action": "cancel"})


# ============================================================================
# CONFIRMATION MODAL
# ============================================================================

class ConfirmationModal(ModalScreen):
    """Confirmation dialog to review parameters before execution"""

    def __init__(self, script_name: str, parameters: dict):
        super().__init__()
        self.script_name = script_name
        self.parameters = parameters
        self.result = None

    def compose(self) -> ComposeResult:
        param_lines = []
        for key, value in self.parameters.items():
            display_value = "••••••••" if "password" in key.lower() else value
            param_lines.append(f"  {key}: {display_value}")

        params_text = "\n".join(param_lines)

        with Container(id="confirm-dialog"):
            yield Label("Confirm Script Execution", id="confirm-title")
            with ScrollableContainer():
                yield Static(
                    f"Script: {self.script_name}\n\nParameters:\n{params_text}\n\nExecute this script with the above parameters?",
                    id="confirm-content"
                )
            yield Horizontal(
                Static("", expand=True),
                Static("[Enter] Execute  [R] Retry  [Esc] Cancel", classes="hotkey-text"),
                Static("", expand=True),
                id="confirm-buttons"
            )

    def on_key(self, event) -> None:
        if event.key == "enter":
            self.result = "execute"
            self.dismiss(self.result)
        elif event.key == "r":
            self.result = "retry"
            self.dismiss(self.result)
        elif event.key == "escape":
            self.result = "cancel"
            self.dismiss(self.result)


# ============================================================================
# SWITCHES MENU MODAL
# ============================================================================

class SwitchesModal(ModalScreen):
    """Switches menu for utility commands"""

    BINDINGS = [
        Binding("escape", "dismiss", "Close", show=False),
        Binding("l", "list_licenses", "List Licenses", show=False),
        Binding("m", "connect_graph", "Connect MgGraph", show=False),
        Binding("e", "connect_exchange", "Connect Exchange", show=False),
    ]

    def compose(self) -> ComposeResult:
        with Container(id="switches-dialog"):
            yield Label("Utility Switches", id="switches-title")
            with ScrollableContainer():
                yield Static("[l] List Available Licenses", classes="switch-option-key", markup=False)
                yield Static("    View all Microsoft 365 licenses in tenant", classes="switch-option-desc")
                yield Static("")
                yield Static("[m] Connect to Microsoft Graph", classes="switch-option-key", markup=False)
                yield Static("    Authenticate to Microsoft Graph API (supports MFA)", classes="switch-option-desc")
                yield Static("")
                yield Static("[e] Connect to Exchange Online", classes="switch-option-key", markup=False)
                yield Static("    Authenticate to Exchange Online (supports MFA)", classes="switch-option-desc")
                yield Static("")
                yield Static("[Esc] Close Menu", classes="switch-option-key", markup=False)

    def action_list_licenses(self) -> None:
        self.dismiss("list_licenses")

    def action_connect_graph(self) -> None:
        self.dismiss("connect_graph")

    def action_connect_exchange(self) -> None:
        self.dismiss("connect_exchange")


# ============================================================================
# MAIN APPLICATION
# ============================================================================

class SysAdminTUI(App):
    """Terminal-style TUI for system administration"""

    CSS_PATH = Path(__file__).parent / "themes" / "terminal.tcss"

    BINDINGS = [
        Binding("q", "quit", "Quit", show=False),
        Binding("d", "toggle_theme", "Theme", show=False),
        Binding("s", "open_switches", "Switches", show=False),
        Binding("up", "cursor_up", "Up", show=False),
        Binding("down", "cursor_down", "Down", show=False),
        Binding("enter", "execute_script", "Execute", show=False),
        Binding("escape", "go_back", "Back", show=False),
    ]

    def __init__(self):
        super().__init__()
        self.config = Config()
        self.script_registry = ScriptRegistry(self.config.scripts_dir)

        # Navigation state
        self.nav_state = "categories"  # "categories" or "scripts"
        self.category_list = self.script_registry.get_categories()
        self.selected_category_index = 0
        self.current_category: str | None = None
        self.script_list: list[str] = []
        self.selected_script_index = 0

        # Execution state
        self.current_input_params = {}
        self.current_script_info = None
        self.awaiting_input = False

        logger.info("SysAdmin TUI started")
        logger.info(f"Log file: {log_file}")
        logger.info(f"Output directory: {self.config.output_dir}")
        logger.info(f"Found {len(self.category_list)} categories, {len(self.script_registry.get_script_list())} scripts total")

    def compose(self) -> ComposeResult:
        with Container(id="script-list-panel"):
            yield Label("Select a Category", id="script-list-title")
            yield ScrollableContainer(
                *self._create_list_items(),
                id="script-list"
            )

        with Container(id="output-panel"):
            yield Label("Output & Execution", id="output-title")
            total = len(self.script_registry.get_script_list())
            yield Static(
                f"Ready.\n\nCategories: {len(self.category_list)}  |  Scripts: {total}\nLog: {log_file.name}\nOutput: {self.config.output_dir}\n\nSelect a category to begin.",
                id="output-content",
                classes="output-ready"
            )

        yield Container(
            Static(
                "[↑↓] Navigate  [Enter] Select  [D] Theme  [Q] Quit",
                classes="hotkey-text",
                id="hotkey-text"
            ),
            id="hotkey-bar"
        )

    def _create_list_items(self) -> list:
        items = []
        if self.nav_state == "categories":
            for idx, cat in enumerate(self.category_list):
                count = len(self.script_registry.get_scripts_in_category(cat))
                classes = "script-item script-item-selected" if idx == self.selected_category_index else "script-item"
                items.append(Static(f" {cat}  ({count} scripts)", classes=classes))
        else:
            for idx, script_name in enumerate(self.script_list):
                info = self.script_registry.get_script_info(script_name)
                display = self.script_registry.get_display_name(script_name)
                indicator = " [S]" if info and info.has_switches else ""
                classes = "script-item script-item-selected" if idx == self.selected_script_index else "script-item"
                items.append(Static(f" {display}{indicator}", classes=classes))
        return items

    def on_mount(self) -> None:
        self.title = "SysAdmin TUI"
        self.sub_title = "Terminal Mode"
        self.theme = "textual-dark"
        logger.info("Application mounted and ready")
        if self.category_list:
            self._show_description()

    def action_toggle_theme(self) -> None:
        if self.theme == "textual-dark":
            self.theme = "textual-light"
            self.notify("Theme: Light")
        else:
            self.theme = "textual-dark"
            self.notify("Theme: Dark")

    def action_cursor_up(self) -> None:
        if self.awaiting_input:
            return
        if self.nav_state == "categories":
            if self.selected_category_index > 0:
                self.selected_category_index -= 1
                self._update_selection()
                self._show_description()
        else:
            if self.selected_script_index > 0:
                self.selected_script_index -= 1
                self._update_selection()
                self._show_description()

    def action_cursor_down(self) -> None:
        if self.awaiting_input:
            return
        if self.nav_state == "categories":
            if self.selected_category_index < len(self.category_list) - 1:
                self.selected_category_index += 1
                self._update_selection()
                self._show_description()
        else:
            if self.selected_script_index < len(self.script_list) - 1:
                self.selected_script_index += 1
                self._update_selection()
                self._show_description()

    def _update_selection(self) -> None:
        container = self.query_one("#script-list", ScrollableContainer)
        items = list(container.query(Static))
        selected = self.selected_category_index if self.nav_state == "categories" else self.selected_script_index
        for idx, item in enumerate(items):
            item.set_classes("script-item script-item-selected" if idx == selected else "script-item")

    def _show_description(self) -> None:
        if self.awaiting_input:
            return
        output = self.query_one("#output-content", Static)

        if self.nav_state == "categories":
            if not self.category_list:
                return
            cat = self.category_list[self.selected_category_index]
            scripts = self.script_registry.get_scripts_in_category(cat)
            text = f"{'='*60}\nCategory: {cat}\n{'='*60}\n\n"
            text += f"{len(scripts)} script{'s' if len(scripts) != 1 else ''} available:\n\n"
            for s in scripts:
                info = self.script_registry.get_script_info(s)
                desc = info.description if info else ""
                display = self.script_registry.get_display_name(s)
                text += f"  • {display}\n    {desc}\n\n"
            text += "\nPress [Enter] to open this category."
        else:
            if not self.script_list:
                return
            script_name = self.script_list[self.selected_script_index]
            info = self.script_registry.get_script_info(script_name)
            if not info:
                return
            display = self.script_registry.get_display_name(script_name)
            text = f"{'='*60}\nScript: {display}\nCategory: {info.category}\n{'='*60}\n\n"
            text += f"{info.description}\n\n"
            if info.parameters:
                text += "Parameters:\n"
                for p in info.parameters:
                    req = "Required" if p.required else "Optional"
                    text += f"  • {p.prompt} ({req})\n"
            else:
                text += "No parameters required.\n"
            if info.has_switches:
                text += f"\n{info.switch_description}\n"
            text += "\nPress [Enter] to execute."

        output.update(text)
        output.set_classes("output-info")

    async def action_execute_script(self) -> None:
        if self.awaiting_input:
            return
        if self.nav_state == "categories":
            await self._enter_category()
        else:
            self._run_selected_script()

    async def _enter_category(self) -> None:
        if not self.category_list:
            return
        self.current_category = self.category_list[self.selected_category_index]
        self.script_list = self.script_registry.get_scripts_in_category(self.current_category)
        self.selected_script_index = 0
        self.nav_state = "scripts"
        await self._rebuild_list_panel()
        self._show_description()
        self.query_one("#hotkey-text", Static).update(
            "[↑↓] Navigate  [Enter] Execute  [S] Switches  [Esc] Categories  [D] Theme  [Q] Quit"
        )

    def _run_selected_script(self) -> None:
        if not self.script_list:
            return
        script_name = self.script_list[self.selected_script_index]
        script_info = self.script_registry.get_script_info(script_name)
        if script_info:
            logger.info(f"Executing script: {script_name}")
            self.run_script_workflow(script_info)

    async def action_go_back(self) -> None:
        if self.awaiting_input or self.nav_state != "scripts":
            return
        self.nav_state = "categories"
        self.current_category = None
        await self._rebuild_list_panel()
        self._show_description()
        self.query_one("#hotkey-text", Static).update(
            "[↑↓] Navigate  [Enter] Select  [D] Theme  [Q] Quit"
        )

    async def _rebuild_list_panel(self) -> None:
        container = self.query_one("#script-list", ScrollableContainer)
        await container.remove_children()
        title = self.query_one("#script-list-title", Label)
        if self.nav_state == "categories":
            title.update("Select a Category")
        else:
            title.update(f"{self.current_category}")
        await container.mount(*self._create_list_items())

    def action_open_switches(self) -> None:
        self.open_switches_menu()

    @work(exclusive=True)
    async def open_switches_menu(self) -> None:
        result = await self.push_screen_wait(SwitchesModal())

        if result == "list_licenses":
            logger.info("List licenses triggered from switches")
            self.run_list_licenses()
        elif result == "connect_graph":
            logger.info("Connect to Microsoft Graph triggered from switches")
            self.run_connect_graph()
        elif result == "connect_exchange":
            logger.info("Connect to Exchange Online triggered from switches")
            self.run_connect_exchange()

    @work(exclusive=True)
    async def run_list_licenses(self) -> None:
        output = self.query_one("#output-content", Static)
        script_info = self.script_registry.get_script_info("MgGraphUserCreation")
        script_path = (
            script_info.path if script_info
            else self.config.scripts_dir / "M365" / "MgGraphUserCreation.ps1"
        )

        output.update("Listing available licenses...\n\nConnecting to Microsoft Graph...")
        output.set_classes("output-running")
        self.notify("Listing licenses...", severity="information")

        stdout_data = []
        stderr_data = []

        try:
            process = await asyncio.create_subprocess_exec(
                "pwsh", "-NoProfile", "-NonInteractive", "-File", str(script_path), "-ListLicenses",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL
            )

            async def read_stream(stream, data_list):
                while True:
                    line = await stream.readline()
                    if not line:
                        break
                    data_list.append(line.decode("utf-8", errors="replace"))
                    if len(data_list) % 3 == 0:
                        output.update(f"Listing Licenses\n\n{'='*60}\n\n{''.join(stdout_data)}")

            await asyncio.gather(
                read_stream(process.stdout, stdout_data),
                read_stream(process.stderr, stderr_data)
            )
            returncode = await process.wait()

            if returncode == 0:
                output.update(f"License Listing Complete\n\n{'='*60}\n\n{''.join(stdout_data)}")
                output.set_classes("output-success")
                self.notify("Licenses listed!", severity="success")
            else:
                error_text = "".join(stderr_data) or "Unknown error"
                output.update(f"Failed to list licenses (exit code: {returncode})\n\n{error_text}")
                output.set_classes("output-error")
                self.notify(f"Failed (exit {returncode})", severity="error")

        except Exception as e:
            output.update(f"Error: {str(e)}")
            output.set_classes("output-error")
            self.notify(f"Error: {str(e)}", severity="error")

    @work(exclusive=True)
    async def run_connect_graph(self) -> None:
        output = self.query_one("#output-content", Static)

        output.update("Connecting to Microsoft Graph...\n\nPlease authenticate when prompted...")
        output.set_classes("output-running")
        self.notify("Connecting to Graph...", severity="information")

        stdout_data = []
        stderr_data = []

        try:
            process = await asyncio.create_subprocess_exec(
                "pwsh", "-NoProfile", "-NonInteractive", "-Command",
                "Connect-MgGraph -Scopes 'User.Read.All','Organization.Read.All','Directory.Read.All'; "
                "Write-Host 'Connected to Microsoft Graph' -ForegroundColor Green; "
                "Get-MgContext | Select-Object -Property Account, Scopes, TenantId | Format-List",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL
            )

            async def read_stream(stream, data_list):
                while True:
                    line = await stream.readline()
                    if not line:
                        break
                    data_list.append(line.decode("utf-8", errors="replace"))
                    if len(data_list) % 2 == 0:
                        output.update(f"Microsoft Graph\n\n{'='*60}\n\n{''.join(stdout_data)}")

            await asyncio.gather(
                read_stream(process.stdout, stdout_data),
                read_stream(process.stderr, stderr_data)
            )
            returncode = await process.wait()

            if returncode == 0:
                output.update(f"Microsoft Graph - Connected\n\n{'='*60}\n\n{''.join(stdout_data)}")
                output.set_classes("output-success")
                self.notify("Connected to Graph!", severity="success")
            else:
                error_text = "".join(stderr_data) or "Connection failed"
                output.update(f"Microsoft Graph - Failed\n\n{error_text}")
                output.set_classes("output-error")
                self.notify("Connection failed", severity="error")

        except Exception as e:
            output.update(f"Error: {str(e)}")
            output.set_classes("output-error")
            self.notify(f"Error: {str(e)}", severity="error")

    @work(exclusive=True)
    async def run_connect_exchange(self) -> None:
        output = self.query_one("#output-content", Static)

        output.update("Connecting to Exchange Online...\n\nPlease authenticate when prompted...")
        output.set_classes("output-running")
        self.notify("Connecting to Exchange...", severity="information")

        stdout_data = []
        stderr_data = []

        try:
            process = await asyncio.create_subprocess_exec(
                "pwsh", "-NoProfile", "-NonInteractive", "-Command",
                "Connect-ExchangeOnline -ShowBanner:$false; "
                "Write-Host 'Connected to Exchange Online' -ForegroundColor Green; "
                "Get-ConnectionInformation | Select-Object -Property UserPrincipalName, TenantId | Format-List",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL
            )

            async def read_stream(stream, data_list):
                while True:
                    line = await stream.readline()
                    if not line:
                        break
                    data_list.append(line.decode("utf-8", errors="replace"))
                    if len(data_list) % 2 == 0:
                        output.update(f"Exchange Online\n\n{'='*60}\n\n{''.join(stdout_data)}")

            await asyncio.gather(
                read_stream(process.stdout, stdout_data),
                read_stream(process.stderr, stderr_data)
            )
            returncode = await process.wait()

            if returncode == 0:
                output.update(f"Exchange Online - Connected\n\n{'='*60}\n\n{''.join(stdout_data)}")
                output.set_classes("output-success")
                self.notify("Connected to Exchange!", severity="success")
            else:
                error_text = "".join(stderr_data) or "Connection failed"
                output.update(f"Exchange Online - Failed\n\n{error_text}")
                output.set_classes("output-error")
                self.notify("Connection failed", severity="error")

        except Exception as e:
            output.update(f"Error: {str(e)}")
            output.set_classes("output-error")
            self.notify(f"Error: {str(e)}", severity="error")

    @work(exclusive=True)
    async def run_script_workflow(self, script_info: ScriptInfo) -> None:
        self.current_script_info = script_info
        self.current_input_params = {}

        if not script_info.parameters:
            await self.execute_script_direct(script_info, {})
            return

        await self.collect_parameters_enhanced()

    async def collect_parameters_enhanced(self) -> None:
        display_name = self.script_registry.get_display_name(self.current_script_info.name)

        while True:
            result = await self.push_screen_wait(
                ParameterInputModal(
                    display_name,
                    self.current_script_info.parameters,
                    self.current_input_params
                )
            )

            if result["action"] == "execute":
                confirm_result = await self.push_screen_wait(
                    ConfirmationModal(display_name, result["values"])
                )

                if confirm_result == "execute":
                    await self.execute_script_direct(self.current_script_info, result["values"])
                    break
                elif confirm_result == "retry":
                    self.current_input_params = result["values"]
                    continue
                else:
                    output = self.query_one("#output-content", Static)
                    output.update("Script execution cancelled.")
                    output.set_classes("output-info")
                    self.notify("Cancelled", severity="information")
                    break
            else:
                output = self.query_one("#output-content", Static)
                output.update("Script execution cancelled.")
                output.set_classes("output-info")
                self.notify("Cancelled", severity="information")
                break

    async def execute_script_direct(self, script_info: ScriptInfo, params: dict) -> None:
        output = self.query_one("#output-content", Static)

        cmd = ["pwsh", "-NoProfile", "-NonInteractive", "-File", str(script_info.path)]
        for param_name, param_value in params.items():
            cmd.extend([f"-{param_name}", param_value])

        display_name = self.script_registry.get_display_name(script_info.name)
        output.update(f"Executing: {display_name}\n\nStarting...")
        output.set_classes("output-running")
        self.notify(f"Running {display_name}...", severity="information")

        stdout_data = []
        stderr_data = []

        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.DEVNULL
            )

            async def read_stream(stream, data_list, is_stderr=False):
                while True:
                    line = await stream.readline()
                    if not line:
                        break
                    data_list.append(line.decode("utf-8", errors="replace"))
                    if len(data_list) % 5 == 0 or is_stderr:
                        current = "".join(stdout_data)
                        if stderr_data:
                            current += "\n\n[Warnings/Errors]\n" + "".join(stderr_data)
                        output.update(f"{display_name}\n\n{'='*60}\n\n{current}")

            await asyncio.gather(
                read_stream(process.stdout, stdout_data),
                read_stream(process.stderr, stderr_data, True)
            )

            returncode = await process.wait()
            final_stdout = "".join(stdout_data)
            final_stderr = "".join(stderr_data)

            if returncode == 0:
                output.update(f"{display_name} - Success\n\n{'='*60}\n\n{final_stdout}")
                output.set_classes("output-success")
                self.notify("Success!", severity="success")
            else:
                error_text = final_stderr or "Script exited with error"
                output.update(f"{display_name} - Failed (exit code: {returncode})\n\n{error_text}\n\n{'='*60}\n\nOutput:\n{final_stdout}")
                output.set_classes("output-error")
                self.notify(f"Failed (exit {returncode})", severity="error")

        except Exception as e:
            output.update(f"Error executing script: {str(e)}")
            output.set_classes("output-error")
            self.notify(f"Error: {str(e)}", severity="error")


def main():
    app = SysAdminTUI()
    try:
        app.run()
    except Exception as e:
        logger.error(f"Application error: {e}")
        raise


if __name__ == "__main__":
    main()
