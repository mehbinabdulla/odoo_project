from PIL import Image

def create_adaptive_foreground():
    source_path = "assets/icon.png"
    output_path = "assets/icon_foreground.png"
    
    # Adaptive icons on Android are 108dp x 108dp, and the safe zone is 66dp (which is ~61% of the total size).
    # We will create a 1024x1024 image, and put the logo in the center 620x620.
    
    with Image.open(source_path) as img:
        # Convert to RGBA for transparency
        img = img.convert("RGBA")
        
        # Determine the size preserving aspect ratio
        max_size = 620
        ratio = min(max_size / img.width, max_size / img.height)
        new_width = int(img.width * ratio)
        new_height = int(img.height * ratio)
        
        resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Create a new transparent 1024x1024 canvas
        canvas = Image.new("RGBA", (1024, 1024), (255, 255, 255, 0))
        
        # Paste the resized image into the center
        offset_x = (1024 - new_width) // 2
        offset_y = (1024 - new_height) // 2
        canvas.paste(resized_img, (offset_x, offset_y), resized_img)
        
        canvas.save(output_path, "PNG")
        print(f"Created {output_path} with proper adaptive icon padding!")

if __name__ == "__main__":
    create_adaptive_foreground()
