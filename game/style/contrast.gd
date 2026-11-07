class_name Contrast
extends RefCounted
## WCAG contrast between two colors (1.0 to 21.0).


static func luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


static func ratio(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
