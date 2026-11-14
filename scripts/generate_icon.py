from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math, json

size=1024
im=Image.new("RGB",(size,size),(9,15,24))
d=ImageDraw.Draw(im)
for y in range(size):
    t=y/size
    d.line((0,y,size,y),fill=(int(8+9*t),int(15+13*t),int(26+12*t)))
green=(111,245,64)
silver=(220,234,239)
# Neon ring
d.arc((140,110,884,855),195,530,fill=(50,132,54),width=35)
d.arc((150,120,874,845),195,530,fill=green,width=14)
# A monogram
d.line([(286,696),(506,233),(738,696)],fill=silver,width=86,joint="curve")
d.line([(363,557),(655,557)],fill=silver,width=67)
# Gamepad silhouette
d.rounded_rectangle((280,495,744,720),radius=95,fill=(21,35,47),outline=green,width=12)
d.line((359,571,359,646),fill=silver,width=24)
d.line((321,609,398,609),fill=silver,width=24)
for x,y in [(648,572),(694,610),(648,648),(604,610)]:
    d.ellipse((x-14,y-14,x+14,y+14),fill=green)
# Download arrow + tray
d.rounded_rectangle((483,678,541,811),radius=13,fill=green)
d.polygon([(430,782),(594,782),(512,870)],fill=green)
d.arc((381,807,643,924),0,180,fill=green,width=24)
out=Path("Sources/Assets.xcassets/AppIcon.appiconset")
out.mkdir(parents=True,exist_ok=True)
im.save(out/"AppIcon.png")
(out/"Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}},indent=2))
