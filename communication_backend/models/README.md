# Aircraft model cache

Place model bundles here on the aircraft edge server. Model files are not
checked into Git. Each model gets its own directory, matching its manifest ID:

```text
models/
  manifest.json
  omnilingual-300m/
    model.int8.onnx
    tokens.txt
```

Start from `manifest.example.json`, update the byte sizes and SHA-256 values,
then copy it to `manifest.json`. Passenger devices must pair with the edge
server before reading the catalogue or downloading a file.
