/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Parses a Mermaid file, lays it out with fixed text sizes and prints the
 * scene. Used by the case tests; also handy for debugging.
 */

int main (string[] args) {
    if (args.length < 2) {
        stderr.printf ("Usage: %s FILE.mmd\n", args[0]);
        return 2;
    }
    string text;
    try {
        FileUtils.get_contents (args[1], out text);
    } catch (FileError e) {
        stderr.printf ("%s\n", e.message);
        return 1;
    }
    try {
        var diagram = Mermaid.parse (text);
        // stdout, not print (): print () converts to the locale's charset.
        stdout.printf ("%s %s\n", diagram.kind, diagram.title ?? "");
        stdout.printf ("%s", diagram.layout (new Mermaid.FixedMeasurer ()).dump ());
    } catch (Mermaid.ParseError e) {
        stdout.printf ("error %s %s\n", e.code.to_string (), e.message);
    }
    return 0;
}
