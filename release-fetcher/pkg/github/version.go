package github

import (
	"fmt"
	"regexp"
	"strconv"
)

func getPreviousVersion(version string) string {
	// Single regex for release-vX.Y.Z or release-vX.Y.x
	re := regexp.MustCompile(`^release-v(\d+)\.(\d+)\.(x|\d+)$`)
	matches := re.FindStringSubmatch(version)
	if len(matches) != 4 {
		return version
	}

	major, _ := strconv.Atoi(matches[1])
	minor, _ := strconv.Atoi(matches[2])
	patchStr := matches[3]

	// Handle .x case
	if patchStr == "x" {
		if minor > 0 {
			return fmt.Sprintf("release-v%d.%d.x", major, minor-1)
		}
		return version
	}

	// Handle standard numeric patch
	patch, _ := strconv.Atoi(patchStr)
	if patch > 0 {
		return fmt.Sprintf("release-v%d.%d.%d", major, minor, patch-1)
	}

	if minor > 0 {
		return fmt.Sprintf("release-v%d.%d.0", major, minor-1)
	}

	return version
}
