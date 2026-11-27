#!/usr/bin/env python3
"""Build an importable Roblox XML model with exact source; no engine execution."""
import argparse,hashlib,xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[1]
xml=ET.Element('roblox',{'version':'4'});ET.SubElement(xml,'External').text='null';ET.SubElement(xml,'External').text='nil'
folder=ET.SubElement(xml,'Item',{'class':'Folder','referent':'RBX0'});props=ET.SubElement(folder,'Properties');ET.SubElement(props,'string',{'name':'Name'}).text='RemoteGuardQuickTest'
entries=[('ModuleScript','RemoteGuard','RemoteGuardRoblox.lua',None),('ModuleScript','RemoteGuardServer','RemoteGuardServer.lua',None),('Script','Smoke','tests/studio_smoke.server.lua',False),('LocalScript','ClientProbe','tests/studio_probe.client.lua',True)]
for i,(cls,name,path,disabled) in enumerate(entries,1):
 item=ET.SubElement(folder,'Item',{'class':cls,'referent':'RBX'+str(i)});props=ET.SubElement(item,'Properties');ET.SubElement(props,'string',{'name':'Name'}).text=name;ET.SubElement(props,'ProtectedString',{'name':'Source'}).text=(root/path).read_text()
 if disabled is not None:ET.SubElement(props,'bool',{'name':'Disabled'}).text=str(disabled).lower()
a.out.parent.mkdir(parents=True,exist_ok=True);ET.ElementTree(xml).write(a.out,encoding='utf-8',xml_declaration=True)
read=ET.parse(a.out).getroot().find('Item');assert read is not None
for item,(_,name,path,disabled) in zip(read.findall('Item'),entries,strict=True):
 props=item.find('Properties');assert props is not None
 source=props.find("ProtectedString[@name='Source']").text;assert source==(root/path).read_text();assert props.find("string[@name='Name']").text==name
 if disabled is not None:assert props.find("bool[@name='Disabled']").text==str(disabled).lower()
 print(name,hashlib.sha256(source.encode()).hexdigest())
print('MODEL',a.out,a.out.stat().st_size)
