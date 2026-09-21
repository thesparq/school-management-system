import urllib.request
import re

url = "https://johnethel.school"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0.4472.124 Safari/537.36'})
try:
    html = urllib.request.urlopen(req).read().decode('utf-8')
    print("Found HTML!")
    # Find all hex colors
    hex_colors = re.findall(r'#[a-fA-F0-9]{3,6}', html)
    from collections import Counter
    print("Top hex colors:")
    for color, count in Counter(hex_colors).most_common(10):
        print(f"{color}: {count}")
    
    # Find style blocks
    styles = re.findall(r'<style[^>]*>(.*?)</style>', html, re.IGNORECASE | re.DOTALL)
    for i, s in enumerate(styles):
        print(f"Style block {i}:")
        print(s[:200])
        print("...")
        
    # Find fonts
    fonts = re.findall(r'font-family:\s*([^;]+);', html)
    print("Fonts found:")
    for font, count in Counter(fonts).most_common(5):
        print(f"{font}: {count}")
        
    # Find CSS links
    css_links = re.findall(r'<link[^>]+rel="stylesheet"[^>]+href="([^"]+)"', html)
    print("CSS links:")
    for link in css_links:
        print(link)
except Exception as e:
    print(e)
