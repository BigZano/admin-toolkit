"""
Script Registry - Auto-discovers PowerShell scripts organized by category subdirectory.

Scripts live at Scripts/<Category>/<script>.ps1
Descriptions auto-extracted from first comment; override via SCRIPT_DESCRIPTIONS.
"""
from pathlib import Path
from typing import Dict, List, Optional
import re
from dataclasses import dataclass


SCRIPT_DESCRIPTIONS: Dict[str, str] = {
    # "ScriptName": "Custom description override",
}


@dataclass
class ScriptParameter:
    name: str
    prompt: str
    default: str = ""
    required: bool = True
    password: bool = False


@dataclass
class ScriptInfo:
    name: str
    path: Path
    description: str
    parameters: List[ScriptParameter]
    category: str = ""
    has_switches: bool = False
    switch_description: str = ""


class ScriptRegistry:
    """Discovers and manages PowerShell scripts from category subdirectories."""

    def __init__(self, scripts_dir: Path):
        self.scripts_dir = scripts_dir
        self.scripts: Dict[str, ScriptInfo] = {}
        self._discover_scripts()

    def _discover_scripts(self) -> None:
        if not self.scripts_dir.exists():
            return
        for category_dir in sorted(self.scripts_dir.iterdir()):
            if not category_dir.is_dir():
                continue
            for script_path in sorted(category_dir.glob("*.ps1")):
                info = self._parse_script(script_path, category_dir.name)
                if info:
                    self.scripts[script_path.stem] = info

    def _parse_script(self, script_path: Path, category: str) -> Optional[ScriptInfo]:
        try:
            content = script_path.read_text(encoding="utf-8")
            name = script_path.stem
            description = SCRIPT_DESCRIPTIONS.get(name) or self._extract_first_comment(content, name)
            parameters = self._extract_parameters(content)
            has_switches = "-ListLicenses" in content or "switch]" in content
            switch_desc = "Supports utility switches (press 'S' for options)" if has_switches else ""
            return ScriptInfo(
                name=name,
                path=script_path,
                description=description,
                parameters=parameters,
                category=category,
                has_switches=has_switches,
                switch_description=switch_desc,
            )
        except Exception as e:
            print(f"Error parsing {script_path}: {e}")
            return None

    def _extract_first_comment(self, content: str, script_name: str) -> str:
        for line in content.split("\n")[:30]:
            stripped = line.strip()
            if not stripped or stripped.startswith("#!"):
                continue
            if stripped.startswith("#"):
                desc = stripped.lstrip("#").strip()
                if len(desc) > 10 and desc.replace("-", "").replace("=", "").strip():
                    return desc
            if not stripped.startswith("#") and not stripped.startswith("<#"):
                break
        return f"PowerShell script: {script_name}"

    def _extract_parameters(self, content: str) -> List[ScriptParameter]:
        parameters = []
        param_match = re.search(r"param\s*\((.*?)\n\)", content, re.DOTALL | re.IGNORECASE)
        if not param_match:
            return parameters
        param_block = param_match.group(1)
        for section in re.split(r",\s*(?=\[)", param_block):
            section = section.strip()
            if not section:
                continue
            mandatory_match = re.search(
                r"\[Parameter\([^)]*Mandatory\s*=\s*\$(\w+)", section, re.IGNORECASE
            )
            is_required = bool(mandatory_match and mandatory_match.group(1).lower() == "true")
            type_name_match = re.search(
                r"\[(\w+)\]\s*\$(\w+)(?:\s*=\s*\"?([^\",\n]*)\"?)?", section
            )
            if not type_name_match:
                continue
            param_type, param_name, default_value = type_name_match.groups()
            default_value = default_value or ""
            if param_type.lower() == "switch":
                continue
            if mandatory_match is None:
                is_required = not (default_value and default_value.strip())
            parameters.append(ScriptParameter(
                name=param_name,
                prompt=self._param_name_to_prompt(param_name),
                default=default_value.strip(),
                required=is_required,
                password="password" in param_name.lower(),
            ))
        return parameters

    def _param_name_to_prompt(self, param_name: str) -> str:
        spaced = re.sub(r"([A-Z])", r" \1", param_name).strip()
        replacements = {
            "Upn": "UPN (User Principal Name)",
            "Sku": "SKU",
            "Mfa": "MFA",
            "Display Name": "Display Name (Full Name)",
            "User Principal Name": "User Principal Name (Email)",
            "Usage Location": "Usage Location (2-letter country code)",
            "Password": "Password (min 8 characters)",
            "New Password": "New Password (min 8 chars, upper/lower/number)",
            "License Index": "License Index (0 to skip, or number from list)",
            "Target User Email": "Target User Email",
            "Mailbox Type": "Mailbox Type (All, UserMailbox, SharedMailbox, etc.)",
            "Username": "Username (SAM account name)",
            "Group Name": "Group Name (AD group name)",
            "Computer Name": "Computer Name (hostname or FQDN)",
            "Days Inactive": "Days Inactive (default: 90)",
            "Days Until Expiry": "Days Until Expiry warning threshold (default: 30)",
            "Report Type": "Report Type (HTML, XML, or Both)",
            "Recursive": "Recursive expansion (true/false)",
            "Force Change At Logon": "Force password change at next logon (true/false)",
            "Path": "Path (folder or drive to scan)",
            "Min Size M B": "Minimum file size in MB (default: 100)",
            "Depth": "Folder depth to report (default: 1)",
            "Days Old": "Files not modified in X days (default: 365)",
            "Recurse": "Recurse into subdirectories (true/false)",
            "Targets": "Host(s) to test — hostname, IP, comma-separated, or path to .txt file",
            "Count": "Number of ping attempts (default: 4)",
            "Port": "Port number(s) — single, comma-separated, or range (e.g. 80,443 or 1-1024)",
            "Port Range": "Port range — 'common', range (e.g. 1-1024), or comma-separated",
            "Timeout Seconds": "Connection timeout in seconds (default: 3)",
            "Record Type": "DNS record type (A, AAAA, MX, NS, CNAME, TXT, PTR, SOA, ALL)",
            "D N S Server": "DNS server to query (blank = system default)",
            "D H C P Server": "DHCP server hostname or IP",
            "Scope Id": "DHCP scope ID to filter (blank = all scopes)",
            "Disabled Users O U": "Disabled Users OU Distinguished Name (optional, e.g. OU=Disabled,DC=domain,DC=com)",
            "Computer List": "Computer(s) — hostname, comma-separated, or path to .txt file (blank = localhost)",
            "Hours Back": "Hours of history to search (default: 24)",
            "Brute Force Threshold": "Failure count to flag as brute force (default: 10)",
            "Include Admin Shares": "Include hidden admin shares C$, ADMIN$, etc. (true/false)",
            "Direction": "Firewall rule direction (Inbound or Outbound)",
            "Enabled Only": "Show only enabled rules (true/false)",
            "Filter Name": "Filter software by name (partial match, blank = all)",
            "Filter Status": "Filter services by status (Running, Stopped, blank = all)",
            "Warn Threshold Pct": "Warning threshold percent used (default: 80)",
            "Crit Threshold Pct": "Critical threshold percent used (default: 90)",
            "First Name": "First Name",
            "Last Name": "Last Name",
            "Title": "Job Title (optional)",
            "Department": "Department (optional)",
            "Target O U": "Target OU (Distinguished Name, blank = default Users OU)",
            "Template User": "Template User (SAM account name to copy groups from, optional)",
            "Source User": "Source User (SAM account name — copy groups FROM this user)",
            "Target User": "Target User (SAM account name — copy groups TO this user)",
            "Disabled O U": "Disabled OU (Distinguished Name, optional — e.g. OU=Disabled,DC=domain,DC=com)",
            "O O O Message": "Out-of-Office Message (optional — set on mailbox during offboarding)",
            "Service Name": "Service Name (Windows service name, e.g. Spooler)",
            "Wait Seconds": "Seconds to wait after service restart (default: 30)",
            "Printer Name": "Printer Name (optional — blank clears all printers on the machine)",
        }
        return replacements.get(spaced, spaced)

    def get_categories(self) -> List[str]:
        return sorted(set(info.category for info in self.scripts.values()))

    def get_scripts_in_category(self, category: str) -> List[str]:
        return sorted(name for name, info in self.scripts.items() if info.category == category)

    def get_script_list(self) -> List[str]:
        return sorted(self.scripts.keys())

    def get_script_info(self, script_name: str) -> Optional[ScriptInfo]:
        return self.scripts.get(script_name)

    def get_display_name(self, script_name: str) -> str:
        name = script_name.replace("_", " ").replace("-", " ")
        name = re.sub(r"\b(script|ps1)\b", "", name, flags=re.IGNORECASE).strip()
        name = re.sub(r"(?<!^)(?=[A-Z])", " ", name)
        acronyms = {"mfa": "MFA", "mg": "Mg", "upn": "UPN", "sku": "SKU", "graph": "Graph"}
        return " ".join(acronyms.get(w.lower(), w.capitalize()) for w in name.split())
