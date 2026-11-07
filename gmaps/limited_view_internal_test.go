package gmaps

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

// mediaItem builds one element of darray[72][0], [51][0] or [37][0] as the
// limited view sends it: id at [0], URL at [6][0], label at [20] and the kind
// at [21][2][1] (3 photo, 4 video, 2 Street View).
func mediaItem(id, link, label string, kind int) []any {
	item := make([]any, 22)
	item[0] = id
	item[6] = []any{link}
	item[20] = label

	if kind != 0 {
		item[21] = []any{nil, nil, []any{float64(10), float64(kind)}}
	}

	return item
}

func limitedDarray(blocks map[int][]any) []any {
	darray := make([]any, 260)
	for idx, items := range blocks {
		darray[idx] = []any{items}
	}

	darray[258] = float64(1)

	return darray
}

func TestLimitedViewImages(t *testing.T) {
	const (
		photoA = "https://lh3.googleusercontent.com/gps-cs-s/AAA=w203-h270-k-no"
		photoB = "https://lh3.googleusercontent.com/gps-cs-s/BBB=w203-h152-k-no"
		photoC = "https://lh3.googleusercontent.com/gps-cs-s/CCC=w203-h100-k-no"
		video  = "https://lh3.googleusercontent.com/gps-cs-s/VVV=w203-h360-k-no"
		sv     = "https://streetviewpixels-pa.googleapis.com/v1/thumbnail?panoid=PANO1&w=211&h=120&yaw=25.5&pitch=0"
		sphere = "https://lh3.googleusercontent.com/gps-cs-s/SSS=w203-h100-k-no"
	)

	darray := limitedDarray(map[int][]any{
		72: {mediaItem("idA", photoA, "Фотографія", 3), mediaItem("idA", photoA, "Фотографія", 3)},
		51: {
			mediaItem("idA", photoA, "Фотографія", 3),
			mediaItem("idV", video, "Відео", 4),
			mediaItem("idB", photoB, "Фотографія", 3),
			mediaItem("idSV", sv, "Перегляд вулиць", 2),
		},
		37: {
			mediaItem("idSV", sv, "Перегляд вулиць", 2),
			mediaItem("idS", sphere, "Street View", 2),
			mediaItem("idB", "https://lh3.googleusercontent.com/gps-cs-s/BBB=w800", "Фотографія", 3),
			mediaItem("", photoC, "", 0),
		},
	})

	got := limitedViewImages(darray)

	require.Equal(t, []Image{
		{Title: "Фотографія", Image: photoA},
		{Title: "Фотографія", Image: photoB},
		{Title: "Street View", Image: sv},
		{Title: "Photo", Image: photoC},
	}, got)

	require.Equal(t,
		"https://www.google.com/maps/@?api=1&map_action=pano&pano=PANO1",
		extractStreetViewURL(got))
}

func TestLimitedViewImagesNothing(t *testing.T) {
	require.Empty(t, limitedViewImages(make([]any, 10)))
	require.Empty(t, limitedViewImages(nil))
}

func TestEntryFromJSONLimitedView(t *testing.T) {
	darray := limitedDarray(map[int][]any{
		72: {mediaItem("idA", "https://lh3.googleusercontent.com/p/A=w203", "Foto", 3)},
		37: {mediaItem("idB", "https://lh3.googleusercontent.com/p/B=w203", "Foto", 3)},
	})

	raw, err := json.Marshal([]any{nil, nil, nil, nil, nil, nil, darray})
	require.NoError(t, err)

	entry, err := EntryFromJSON(raw)
	require.NoError(t, err)
	require.Len(t, entry.Images, 2)
	require.Empty(t, entry.StreetViewURL)
}

func TestEntryFromJSONFullGalleryWins(t *testing.T) {
	darray := limitedDarray(map[int][]any{
		72: {mediaItem("idA", "https://lh3.googleusercontent.com/p/A=w203", "Foto", 3)},
	})
	darray[171] = []any{[]any{
		[]any{nil, nil, "Todas", []any{[]any{nil, nil, nil, nil, nil, nil, []any{"https://lh3.googleusercontent.com/p/G=w203"}}}},
	}}

	raw, err := json.Marshal([]any{nil, nil, nil, nil, nil, nil, darray})
	require.NoError(t, err)

	entry, err := EntryFromJSON(raw)
	require.NoError(t, err)
	require.Equal(t, []Image{{Title: "Todas", Image: "https://lh3.googleusercontent.com/p/G=w203"}}, entry.Images)
}
