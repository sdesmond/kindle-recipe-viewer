# Bundled fonts

`AtkinsonHyperlegible-Regular.ttf` and `AtkinsonHyperlegible-Bold.ttf` are the
static Atkinson Hyperlegible Next builds from the official
`googlefonts/atkinson-hyperlegible-next` repository. They are licensed under
the SIL Open Font License 1.1 in `OFL.txt`.

The compiler transliterates accented Latin characters because the source
recipe viewer's physical display tests found a glyph-advance defect in its
other renderer. Keeping that normalization here also makes wrapping and
command-log fixtures deterministic across host and Kindle font stacks.

