package github

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/google/go-github/v81/github"
	"golang.org/x/oauth2"
)

func GetPRListForRelease(ctx context.Context, repo Repository, version string) (map[string][]string, error) {
	ts := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: ctx.Value(GITHUB_TOKEN).(string)},
	)
	tc := oauth2.NewClient(ctx, ts)
	client := github.NewClient(tc)

	head := version
	base := getPreviousVersion(version)

	comparison, _, err := client.Repositories.CompareCommits(ctx, repo.Owner, repo.Repo, base, head, nil)
	if err != nil {
		log.Fatal(err)
	}

	prList := make(map[string][]string)

	for _, commit := range comparison.Commits {
		prs, _, err := client.PullRequests.ListPullRequestsWithCommit(ctx, repo.Owner, repo.Repo, commit.GetSHA(), nil)
		if err != nil {
			fmt.Printf("Error fetching PRs for commit %s: %v\n", commit.GetSHA(), err)
			continue
		}
		commitMessage := strings.Split(commit.Commit.GetMessage(), "\n\n")[0]
		for _, pr := range prs {
			prURL := pr.GetHTMLURL()
			if _, ok := prList[prURL]; !ok {
				prList[prURL] = []string{commitMessage}
			} else {
				prList[prURL] = append(prList[prURL], commitMessage)
			}
		}
	}

	return prList, nil
}
