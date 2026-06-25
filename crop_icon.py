from PIL import Image

def crop_transparent_padding(input_path, output_path):
    try:
        img = Image.open(input_path).convert("RGBA")
        bbox = img.getbbox()
        if bbox:
            # bbox is (left, upper, right, lower)
            img_cropped = img.crop(bbox)
            
            # Make it square by padding the smaller dimension
            width, height = img_cropped.size
            max_dim = max(width, height)
            
            # Create a new transparent square image
            new_img = Image.new("RGBA", (max_dim, max_dim), (0, 0, 0, 0))
            
            # Paste the cropped image into the center
            offset = ((max_dim - width) // 2, (max_dim - height) // 2)
            new_img.paste(img_cropped, offset)
            
            new_img.save(output_path, "PNG")
            print("Success")
        else:
            print("Image is entirely transparent")
    except Exception as e:
        print(f"Error: {e}")

crop_transparent_padding(r"c:\Users\rodra\music_separator_project\flutter_app_folder\assets\images\app_icon.png", r"c:\Users\rodra\music_separator_project\flutter_app_folder\assets\images\app_icon.png")
