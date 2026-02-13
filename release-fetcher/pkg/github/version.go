package github

import (
	"fmt"
	"regexp"
	"strconv"
)

func getPreviousVersion(version string) string {
	// regex to match release-vX.Y.Z
	re := regexp.MustCompile(`^release-v(\d+)\.(\d+)\.(\d+)$`)
	matches := re.FindStringSubmatch(version)
	if len(matches) != 4 {
		return version
	}

	major, _ := strconv.Atoi(matches[1])
	minor, _ := strconv.Atoi(matches[2])
	patch, _ := strconv.Atoi(matches[3])

	if patch > 0 {
		return fmt.Sprintf("release-v%d.%d.%d", major, minor, patch-1)
	}

	if minor > 0 {
		return fmt.Sprintf("release-v%d.%d.0", major, minor-1)
	}

	// Fallback for 0.0.0 or similar
	return version
}
