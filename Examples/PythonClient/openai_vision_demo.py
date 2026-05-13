"""Real vision end-to-end test via official openai SDK.

Builds a 256x256 test image with three distinct colored squares,
sends it to pfm-serve-mlx (which must be running with FastVLM
loaded), and prints the model's description.
"""
import base64
import io
import sys
from openai import OpenAI

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Missing PIL — run: pip install pillow", file=sys.stderr)
    sys.exit(1)

# Build a clearly described test image.
img = Image.new("RGB", (256, 256), color=(40, 40, 40))
draw = ImageDraw.Draw(img)
# Three squares: red top-left, green top-right, blue bottom-middle
draw.rectangle((20, 20, 100, 100), fill=(200, 30, 30))
draw.rectangle((156, 20, 236, 100), fill=(30, 200, 30))
draw.rectangle((88, 140, 168, 220), fill=(30, 80, 220))

buf = io.BytesIO()
img.save(buf, format="PNG")
b64 = base64.b64encode(buf.getvalue()).decode()

client = OpenAI(base_url="http://127.0.0.1:11434/v1", api_key="x")
resp = client.chat.completions.create(
    model="mlx-FastVLM",
    messages=[{
        "role": "user",
        "content": [
            {"type": "text", "text": "Describe the image. List the colored shapes you see and their positions."},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64}"}},
        ],
    }],
    max_tokens=200,
    temperature=0,
)
print("Vision response:")
print("=" * 60)
print(resp.choices[0].message.content)
print("=" * 60)
print(f"\nGround truth: red square top-left, green square top-right, blue square bottom-center.")
