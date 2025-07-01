## Releasing a new version

To release a new version:

1. Update the `version` constant in quickss.swift.
2. Update `CHANGES.md` with the correct version number.
3. Add to git, commit and push.
4. Run `./notarise.sh` to compile the `quickss` binary, sign and notarise it.
5. Tag with `git tag -s <version number>` and push.
6. Create the updated Alfred workflow:
   a. Open Alfred Preferences and select the QuickSS workflow.
   b. Right click on the workflow and select "Open in Finder"
   c. Copy `quickss` into the workflow's folder.
   c. Update the version number in the "About this Workflow" dialog.
   d. Export the Workflow
7. Generate a GitHub Release and upload the `quickss` binary to it.
