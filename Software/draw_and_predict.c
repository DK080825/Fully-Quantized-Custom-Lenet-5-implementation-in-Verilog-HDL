import tkinter as tk
from tkinter import messagebox
from PIL import Image, ImageDraw, ImageOps
import subprocess
import numpy as np

CANVAS_SIZE = 280
IMG_SIZE = 28
BRUSH_RADIUS = 10

TEMP_TXT = "drawn_digit.txt"

# đổi thành executable thật của bạn
INFER_EXE = "./lenet_single_infer"   # Linux
# INFER_EXE = "lenet_single_infer.exe"  # Windows


class DrawPredictApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Draw Digit and Predict")

        self.canvas = tk.Canvas(root, width=CANVAS_SIZE, height=CANVAS_SIZE, bg="black")
        self.canvas.grid(row=0, column=0, columnspan=3, padx=10, pady=10)

        self.btn_predict = tk.Button(root, text="Predict", width=12, command=self.predict)
        self.btn_predict.grid(row=1, column=0, pady=10)

        self.btn_clear = tk.Button(root, text="Clear", width=12, command=self.clear)
        self.btn_clear.grid(row=1, column=1, pady=10)

        self.btn_save = tk.Button(root, text="Save 28x28 TXT", width=12, command=self.save_txt_only)
        self.btn_save.grid(row=1, column=2, pady=10)

        self.result_label = tk.Label(root, text="Prediction: -", font=("Arial", 14))
        self.result_label.grid(row=2, column=0, columnspan=3, pady=5)

        self.latency_label = tk.Label(root, text="Latency: -", font=("Arial", 14))
        self.latency_label.grid(row=3, column=0, columnspan=3, pady=5)

        self.image = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), color=0)
        self.draw = ImageDraw.Draw(self.image)

        self.last_x = None
        self.last_y = None

        self.canvas.bind("<Button-1>", self.on_button_press)
        self.canvas.bind("<B1-Motion>", self.on_draw)
        self.canvas.bind("<ButtonRelease-1>", self.on_button_release)

    def on_button_press(self, event):
        self.last_x = event.x
        self.last_y = event.y
        self.draw_circle(event.x, event.y)

    def on_draw(self, event):
        if self.last_x is not None and self.last_y is not None:
            self.canvas.create_line(
                self.last_x, self.last_y, event.x, event.y,
                fill="white", width=BRUSH_RADIUS * 2,
                capstyle=tk.ROUND, smooth=True
            )
            self.draw.line(
                [self.last_x, self.last_y, event.x, event.y],
                fill=255, width=BRUSH_RADIUS * 2
            )
            self.draw_circle(event.x, event.y)
        self.last_x = event.x
        self.last_y = event.y

    def on_button_release(self, event):
        self.last_x = None
        self.last_y = None

    def draw_circle(self, x, y):
        r = BRUSH_RADIUS
        self.canvas.create_oval(x-r, y-r, x+r, y+r, fill="white", outline="white")
        self.draw.ellipse((x-r, y-r, x+r, y+r), fill=255)

    def clear(self):
        self.canvas.delete("all")
        self.image = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), color=0)
        self.draw = ImageDraw.Draw(self.image)
        self.result_label.config(text="Prediction: -")
        self.latency_label.config(text="Latency: -")

    def preprocess_to_uint8_vector(self):
        img = self.image.copy()

        # resize về 28x28
        img = img.resize((IMG_SIZE, IMG_SIZE), Image.Resampling.LANCZOS)

        # MNIST thường là digit trắng nền đen; nếu model của bạn training ngược thì invert ở đây
        # img = ImageOps.invert(img)

        arr = np.array(img, dtype=np.uint8)

        # flatten thành 784 giá trị uint8
        vec = arr.reshape(-1)
        return vec

    def save_txt_only(self):
        vec = self.preprocess_to_uint8_vector()
        with open(TEMP_TXT, "w", encoding="utf-8") as f:
            f.write(" ".join(str(int(v)) for v in vec.tolist()))
            f.write("\n")
        messagebox.showinfo("Saved", f"Saved 28x28 uint8 image to {TEMP_TXT}")

    def predict(self):
        try:
            vec = self.preprocess_to_uint8_vector()

            with open(TEMP_TXT, "w", encoding="utf-8") as f:
                f.write(" ".join(str(int(v)) for v in vec.tolist()))
                f.write("\n")

            result = subprocess.run(
                [INFER_EXE, TEMP_TXT],
                capture_output=True,
                text=True,
                check=True
            )

            pred = None
            latency = None

            for line in result.stdout.splitlines():
                if line.startswith("Prediction:"):
                    pred = line.split(":")[1].strip()
                elif line.startswith("Latency_us:"):
                    latency = line.split(":")[1].strip()

            if pred is None or latency is None:
                raise RuntimeError("Could not parse inference output.")

            self.result_label.config(text=f"Prediction: {pred}")
            self.latency_label.config(text=f"Latency: {latency} us")

        except subprocess.CalledProcessError as e:
            messagebox.showerror("Inference Error", e.stderr if e.stderr else str(e))
        except Exception as e:
            messagebox.showerror("Error", str(e))


if __name__ == "__main__":
    root = tk.Tk()
    app = DrawPredictApp(root)
    root.mainloop()