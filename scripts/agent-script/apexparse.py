"""Reads @InvocableMethod / @InvocableVariable metadata from the NXP agent action classes."""
import re, os

def _attr(block, name):
    m = re.search(name + r"\s*=\s*'((?:[^'\\]|\\.)*)'", block, re.S)
    return m.group(1).replace("\\'", "'") if m else None

def parse(path):
    src = open(path).read()
    out = {"class": os.path.basename(path)[:-4], "inputs": [], "outputs": []}
    m = re.search(r"@InvocableMethod\((.*?)\)\s*public static", src, re.S)
    out["label"] = _attr(m.group(1), "label")
    out["description"] = _attr(m.group(1), "description")
    for section, key in (("Request", "inputs"), ("Response", "outputs")):
        sm = re.search(r"public class " + section + r"\s*\{(.*?)\n    \}", src, re.S)
        if not sm:
            continue
        for vm in re.finditer(r"@InvocableVariable\((.*?)\)\s*public (\w+) (\w+);", sm.group(1), re.S):
            block, typ, name = vm.groups()
            out[key].append({
                "name": name, "apexType": typ,
                "label": _attr(block, "label"),
                "description": _attr(block, "description") or "",
                "required": bool(re.search(r"required\s*=\s*true", block)),
            })
    return out
