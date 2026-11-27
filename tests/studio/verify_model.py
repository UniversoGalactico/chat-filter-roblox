"""Check the checked-in model contains exactly the reviewed scripts (XML, not Studio loading)."""
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
root=ET.parse(ROOT/"tests/studio/ChatFilterTest.rbxmx").getroot()
folder=root.find("Item")
assert folder.attrib["class"]=="Folder"
actual={}
for item in folder.findall("Item"):
    p=item.find("Properties")
    name=p.find("string[@name='Name']").text
    assert name not in actual
    actual[name]=(item.attrib["class"],p.find("ProtectedString[@name='Source']").text)
expected={name:("ModuleScript",(ROOT/"server"/(name+".lua")).read_text()) for name in ("ChatFilter","DeliveryGate","ContextPolicy")}
expected["Smoke"]=("Script",(ROOT/"tests/studio/Smoke.server.lua").read_text())
assert actual==expected, "Studio model differs from reviewed source"
print("PASS: importable model XML matches all four source files")
