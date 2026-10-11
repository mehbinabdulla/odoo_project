from PIL import Image
import os

def resize_icon():
    source_path = "assets/icon.png"
    sizes = [48, 72, 96, 144, 192]
    
    if not os.path.exists(source_path):
        print(f"Source file {source_path} not found!")
        return

    try:
        with Image.open(source_path) as img:
            for size in sizes:
                resized_img = img.resize((size, size), Image.Resampling.LANCZOS)
                output_path = f"assets/icon_{size}x{size}.png"
                resized_img.save(output_path, "PNG")
                print(f"Created: {output_path}")
    except Exception as e:
        print(f"Error resizing icon: {e}")

if __name__ == "__main__":
    resize_icon()
