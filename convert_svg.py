from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM

def convert_svg_to_png(svg_path, png_path):
    print(f"Converting {svg_path} to {png_path}...")
    drawing = svg2rlg(svg_path)
    if drawing is None:
        print("Failed to read SVG")
        return
    renderPM.drawToFile(drawing, png_path, fmt="PNG")
    print("Done!")

if __name__ == "__main__":
    convert_svg_to_png("assets/icon.svg", "assets/icon.png")
