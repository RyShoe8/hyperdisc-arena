## QR codes (ISO/IEC 18004), enough for a join link: byte mode, error
## correction level M, versions 1-10 (up to 213 bytes). Follows the structure
## of Project Nayuki's reference encoder.
##
##   var qr := QrCode.encode("https://playbound.club/c/ABC123")
##   qr.size, qr.dark(x, y)
extends RefCounted

## Level M, indexed by version (0 unused).
const ECC_PER_BLOCK := [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const NUM_BLOCKS := [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const FORMAT_ECL_M := 0
const MAX_VERSION := 10

var version := 1
var size := 21
var mask := 0
var _modules := PackedByteArray()
var _function := PackedByteArray()


func dark(x: int, y: int) -> bool:
	return _modules[y * size + x] == 1


## Returns null if the text is too long for version 10.
static func encode(text: String):
	var data := text.to_utf8_buffer()
	var ver := 1
	while ver <= MAX_VERSION:
		var count_bits := 8 if ver < 10 else 16
		if 4 + count_bits + data.size() * 8 <= _data_codewords(ver) * 8:
			break
		ver += 1
	if ver > MAX_VERSION:
		return null
	# Bit stream: mode, length, bytes, terminator, padding.
	var bits: Array[int] = []
	_append(bits, 0b0100, 4)
	_append(bits, data.size(), 8 if ver < 10 else 16)
	for b in data:
		_append(bits, b, 8)
	var capacity := _data_codewords(ver) * 8
	_append(bits, 0, mini(4, capacity - bits.size()))
	_append(bits, 0, (8 - bits.size() % 8) % 8)
	var codewords := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var v := 0
		for j in 8:
			v = (v << 1) | bits[i + j]
		codewords.append(v)
	var pad := 0xEC
	while codewords.size() < _data_codewords(ver):
		codewords.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC

	var qr = new()
	qr.version = ver
	qr.size = ver * 4 + 17
	qr._modules.resize(qr.size * qr.size)
	qr._function.resize(qr.size * qr.size)
	qr._draw_function_patterns()
	qr._draw_codewords(_add_ecc_and_interleave(codewords, ver))
	# Pick the mask with the lowest penalty, as the standard asks.
	var best := -1
	var best_score := 1 << 30
	for m in 8:
		qr._apply_mask(m)
		qr._draw_format_bits(m)
		var score: int = qr._penalty()
		if score < best_score:
			best = m
			best_score = score
		qr._apply_mask(m)  # XOR again to undo
	qr.mask = best
	qr._apply_mask(best)
	qr._draw_format_bits(best)
	return qr


static func _append(bits: Array[int], value: int, length: int) -> void:
	for i in range(length - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _raw_data_modules(ver: int) -> int:
	var result := (16 * ver + 128) * ver + 64
	if ver >= 2:
		var num_align := ver / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if ver >= 7:
			result -= 36
	return result


static func _data_codewords(ver: int) -> int:
	return _raw_data_modules(ver) / 8 - ECC_PER_BLOCK[ver] * NUM_BLOCKS[ver]


# --- Error correction --------------------------------------------------------

static func _add_ecc_and_interleave(data: PackedByteArray, ver: int) -> PackedByteArray:
	var num_blocks: int = NUM_BLOCKS[ver]
	var ecc_len: int = ECC_PER_BLOCK[ver]
	var raw_codewords := _raw_data_modules(ver) / 8
	var num_short := num_blocks - raw_codewords % num_blocks
	var short_len := raw_codewords / num_blocks
	var divisor := _rs_divisor(ecc_len)
	var blocks: Array[PackedByteArray] = []
	var k := 0
	for i in num_blocks:
		var data_len := short_len - ecc_len + (0 if i < num_short else 1)
		var dat := data.slice(k, k + data_len)
		k += data_len
		var ecc := _rs_remainder(dat, divisor)
		if i < num_short:
			dat.append(0)  # placeholder so all blocks line up
		dat.append_array(ecc)
		blocks.append(dat)
	var result := PackedByteArray()
	for i in blocks[0].size():
		for j in blocks.size():
			# Skip the placeholder byte of short blocks.
			if i != short_len - ecc_len or j >= num_short:
				result.append(blocks[j][i])
	return result


static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor := b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in result.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


# --- Drawing -----------------------------------------------------------------

func _set_function(x: int, y: int, is_dark: bool) -> void:
	_modules[y * size + x] = 1 if is_dark else 0
	_function[y * size + x] = 1


func _draw_function_patterns() -> void:
	for i in size:
		_set_function(6, i, i % 2 == 0)
		_set_function(i, 6, i % 2 == 0)
	_draw_finder(3, 3)
	_draw_finder(size - 4, 3)
	_draw_finder(3, size - 4)
	var align := _alignment_positions()
	var n := align.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			_draw_alignment(align[i], align[j])
	_draw_format_bits(0)  # reserves the format area; redrawn once masked
	_draw_version()


func _draw_finder(cx: int, cy: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and x < size and y >= 0 and y < size:
				var dist := maxi(absi(dx), absi(dy))
				_set_function(x, y, dist != 2 and dist != 4)


func _draw_alignment(cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_function(cx + dx, cy + dy, maxi(absi(dx), absi(dy)) != 1)


func _alignment_positions() -> Array[int]:
	var result: Array[int] = []
	if version == 1:
		return result
	var num_align := version / 7 + 2
	var step := int(ceil(float(version * 4 + 4) / float(num_align * 2 - 2))) * 2
	result.append(6)
	var pos := size - 7
	while result.size() < num_align:
		result.insert(1, pos)
		pos -= step
	return result


func _draw_format_bits(m: int) -> void:
	var data := (FORMAT_ECL_M << 3) | m
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_function(8, i, (bits >> i) & 1 == 1)
	_set_function(8, 7, (bits >> 6) & 1 == 1)
	_set_function(8, 8, (bits >> 7) & 1 == 1)
	_set_function(7, 8, (bits >> 8) & 1 == 1)
	for i in range(9, 15):
		_set_function(14 - i, 8, (bits >> i) & 1 == 1)
	for i in range(0, 8):
		_set_function(size - 1 - i, 8, (bits >> i) & 1 == 1)
	for i in range(8, 15):
		_set_function(8, size - 15 + i, (bits >> i) & 1 == 1)
	_set_function(8, size - 8, true)  # always dark


func _draw_version() -> void:
	if version < 7:
		return
	var rem := version
	for i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits := (version << 12) | rem
	for i in 18:
		var bit := (bits >> i) & 1 == 1
		var a := size - 11 + i % 3
		var b := i / 3
		_set_function(a, b, bit)
		_set_function(b, a, bit)


func _draw_codewords(data: PackedByteArray) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if _function[y * size + x] == 0 and i < data.size() * 8:
					_modules[y * size + x] = (data[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


func _apply_mask(m: int) -> void:
	for y in size:
		for x in size:
			if _function[y * size + x] == 1:
				continue
			var invert := false
			match m:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				_modules[y * size + x] ^= 1


## The standard's four penalty rules (lower scans more reliably).
func _penalty() -> int:
	var score := 0
	var dark_count := 0
	for pass_ in 2:  # rows, then columns
		for a in size:
			var run := 0
			var last := -1
			var line := ""
			for b in size:
				var v := _modules[a * size + b] if pass_ == 0 else _modules[b * size + a]
				line += "1" if v == 1 else "0"
				if pass_ == 0 and v == 1:
					dark_count += 1
				if v == last:
					run += 1
					if run == 5:
						score += 3
					elif run > 5:
						score += 1
				else:
					run = 1
					last = v
			var padded := "0000" + line + "0000"
			score += 40 * (padded.count("10111010000") + padded.count("00001011101"))
	for y in size - 1:
		for x in size - 1:
			var v := _modules[y * size + x]
			if v == _modules[y * size + x + 1] and v == _modules[(y + 1) * size + x] \
					and v == _modules[(y + 1) * size + x + 1]:
				score += 3
	var total := size * size
	var k := int(absf(dark_count * 100.0 / total - 50.0) / 5.0)
	score += k * 10
	return score
