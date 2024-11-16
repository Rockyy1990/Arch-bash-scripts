#!/usr/bin/env python

import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, Listbox, Scrollbar
import tkinter.font as tkFont
import os

class TextEditor:
    def __init__(self, root):
        self.root = root
        self.root.title("Simple Text Editor")
        self.root.geometry("800x600")

        # Create Text Widget
        self.text_area = tk.Text(self.root)
        self.text_area.pack(expand=1, fill='both')

        # Create Menu
        self.create_menu()

        # Initialize file path
        self.file_path = None

    def create_menu(self):
        menu = tk.Menu(self.root)
        self.root.config(menu=menu)

        file_menu = tk.Menu(menu, tearoff=0)
        file_menu.add_command(label="New", command=self.new_file)
        file_menu.add_command(label="Open", command=self.open_file)
        file_menu.add_command(label="Save", command=self.save_file)
        file_menu.add_command(label="Save As", command=self.save_as)
        menu.add_cascade(label="File", menu=file_menu)

        edit_menu = tk.Menu(menu, tearoff=0)
        edit_menu.add_command(label="Add Line Break", command=self.add_line_break)
        edit_menu.add_command(label="Change Font", command=self.change_font)
        menu.add_cascade(label="Edit", menu=edit_menu)

    def new_file(self):
        self.text_area.delete(1.0, tk.END)
        self.file_path = None

    def open_file(self):
        file_path = filedialog.askopenfilename(filetypes=[("Text files", "*.txt;*.sh;*.py;*.odt;*.rtf")])
        if file_path:
            self.file_path = file_path
            with open(file_path, 'r') as file:
                self.text_area.delete(1.0, tk.END)
                self.text_area.insert(tk.END, file.read())

    def save_file(self):
        if not self.file_path:
            self.save_as()
        else:
            with open(self.file_path, 'w') as file:
                file.write(self.text_area.get(1.0, tk.END))

    def save_as(self):
        file_path = filedialog.asksaveasfilename(defaultextension=".txt", filetypes=[("Text files", "*.txt"), ("Shell scripts", "*.sh"), ("Python files", "*.py"), ("ODT files", "*.odt"), ("RTF files", "*.rtf")])
        if file_path:
            self.file_path = file_path
            with open(self.file_path, 'w') as file:
                file.write(self.text_area.get(1.0, tk.END))

    def add_line_break(self):
        # Insert a line break at the current cursor position
        self.text_area.insert(tk.END, '\n')

    def change_font(self):
        font_list = list(tkFont.families())
        font_window = tk.Toplevel(self.root)
        font_window.title("Select Font")
        
        listbox = Listbox(font_window, selectmode=tk.SINGLE)
        for font in font_list:
            listbox.insert(tk.END, font)
        listbox.pack(expand=True, fill='both')
        
        button_ok = tk.Button(font_window, text="Select", command=lambda: self.set_font(listbox.get(listbox.curselection())))
        button_ok.pack()

    def set_font(self, font_name):
        self.text_area.configure(font=(font_name, 12))  # Set a default size, you can modify it based on requirement
        self.text_area.focus()

if __name__ == "__main__":
    root = tk.Tk()
    editor = TextEditor(root)
    root.mainloop()
