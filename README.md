# 🧩 multi-mesh - Render Massive Swarms With Ease

[![Download / Visit](https://img.shields.io/badge/Download-Visit%20the%20Repo-blue?style=for-the-badge&logo=github)](https://github.com/roachseniti446/multi-mesh)

## 📥 Download
Visit this page to download the app and open the project files:
https://github.com/roachseniti446/multi-mesh

## 🖥️ What This Project Is
multi-mesh is a Godot 4 project about drawing huge groups of moving objects on screen.

It shows how to handle very large swarms, flocks, and particle-like effects without overloading the computer. The project starts with simple node-based scenes and moves toward GPU-based rendering. It uses compute shaders, stream compaction, and indirect draws to push more work to the graphics card.

If you want to see how games can display 100,000 to 1,000,000 moving objects, this repo shows the path.

## 🚀 Getting Started on Windows

1. Open the download page:
   https://github.com/roachseniti446/multi-mesh

2. On the GitHub page, look for the latest release or the main project files.

3. Download the project files to your computer.

4. If you get a zip file, right-click it and choose **Extract All**.

5. Open the extracted folder.

6. Look for the Godot project file, usually named `project.godot`.

7. If you already have Godot 4 installed, open Godot and load the project from that file.

8. If the project includes a Windows build, open the `.exe` file to run it.

9. If you see a first-time setup prompt, allow the project to finish loading.

## 🧰 What You Need

- Windows 10 or Windows 11
- A modern graphics card
- At least 8 GB of RAM
- Enough free disk space for the project files
- Godot 4 if you want to open the project files

## 🖱️ How to Run It

### Option 1: Open the Project in Godot
Use this if you want to inspect the project.

1. Download the project from:
   https://github.com/roachseniti446/multi-mesh

2. Extract the files if needed.

3. Start Godot 4.

4. Click **Import** or **Open**.

5. Select the folder that contains `project.godot`.

6. Wait for Godot to load the project.

7. Press the play button inside Godot.

### Option 2: Run a Windows Build
Use this if the repo includes a ready-to-run build.

1. Download the release files from:
   https://github.com/roachseniti446/multi-mesh

2. Extract the files if they are in a zip archive.

3. Find the `.exe` file.

4. Double-click it.

5. If Windows asks for permission, choose **Run**.

## 🎮 What You Will See

When the project runs, it focuses on large-scale motion on screen. The scene is meant to show:

- Huge groups of moving objects
- Fast object updates
- GPU-based culling
- Reduced CPU load
- Many swarms running at once

The project also helps show the cost of drawing too many objects the old way. It compares simple node methods with lower-level GPU methods.

## 🔧 Main Features

- Renders very large numbers of instances
- Uses Godot 4 rendering tools
- Moves work from CPU to GPU
- Uses compute shaders for heavy updates
- Uses stream compaction to remove unused objects
- Uses indirect draws for faster rendering
- Supports many independent swarms
- Helps you see where performance drops start

## 🧪 Performance Notes

This project is made to test limits.

It shows how far Godot 4 can go when you push a lot of moving instances at once. It also shows two main costs:

- **Copy tax**: moving data between memory and the GPU
- **Draw call tax**: the cost of asking the engine to draw many things

The project is useful if you want to learn why some scenes run well and others slow down fast.

## 📁 Project Files

Common files you may see in this repo:

- `project.godot` - the main Godot project file
- `scenes/` - scene files
- `scripts/` - logic files
- `shaders/` - GPU shader files
- `assets/` - images and other media
- `README.md` - project instructions

## 🧭 First Time Use

After opening the project for the first time:

1. Let Godot finish importing files
2. Wait for shaders to compile
3. Open the main scene
4. Press Play
5. Watch the swarm render on screen

If the scene is slow on your PC, reduce the number of instances in the project settings or test scene.

## 🛠️ Common Problems

### The project does not open
- Check that you installed Godot 4
- Make sure you selected the folder with `project.godot`
- Confirm that the download finished

### The screen is blank
- Wait for the project to finish loading
- Open the correct main scene
- Make sure your graphics driver is up to date

### It runs slowly
- Close other apps
- Lower the instance count
- Use a newer graphics card if possible
- Run the project on a system with more VRAM

### Windows blocks the file
- Right-click the `.exe`
- Choose **Properties**
- Select **Unblock** if it appears
- Run the file again

## 🧠 What This Repo Teaches
This project is useful if you want to understand:

- Why node-heavy scenes can slow down
- How the GPU can help with large groups
- How culling removes objects that do not need drawing
- How indirect drawing reduces overhead
- How a million moving objects can still be hard to manage

## 📌 Best Use Case
This repo fits users who want to:

- Test large-scale rendering
- Learn how swarm effects work
- See GPU-driven drawing in Godot 4
- Study the limits of real-time rendering

## 🔍 Suggested Setup
For the smoothest experience on Windows:

- Use Godot 4.2 or newer
- Update your GPU driver
- Use a desktop PC with a dedicated graphics card
- Keep at least 2 GB free for the project and cache files
- Close heavy background apps before running the demo

## 📎 Download Again
If you need the files again, visit:
https://github.com/roachseniti446/multi-mesh

## 🧩 File Path Example
If you extracted the project to your Downloads folder, the path may look like:

`C:\Users\YourName\Downloads\multi-mesh\project.godot`

Open that file in Godot to load the project

## 🎯 Main Goal
This project shows how far Godot 4 can go when it renders massive swarms without using a lot of CPU time