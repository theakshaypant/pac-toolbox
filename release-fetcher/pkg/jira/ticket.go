package jira

import (
	"context"
	"fmt"

	"github.com/andygrunwald/go-jira"
)

func initiJiraClient(ctx context.Context) (*jira.Client, error) {
	tp := jira.BearerAuthTransport{
		Token: ctx.Value(JIRA_TOKEN).(string),
	}
	client, err := jira.NewClient(tp.Client(), ctx.Value(JIRA_URL).(string))
	if err != nil {
		return nil, fmt.Errorf("failed to create Jira client: %w", err)
	}

	return client, nil
}

func GetTicketFromPR(ctx context.Context, prURL string) []string {
	client, _ := initiJiraClient(ctx)
	options := &jira.SearchOptions{
		MaxResults: 50,
	}

	jqlQuery := fmt.Sprintf(`"Git Pull Request" ~ "%s"`, prURL)

	issues, _, err := client.Issue.Search(jqlQuery, options)
	if err != nil {
		fmt.Println(err)
		return nil
	}

	issuesURL := make([]string, len(issues))
	for idx, issue := range issues {
		issuesURL[idx] = fmt.Sprintf("https://%s/browse/%s", ctx.Value(JIRA_URL).(string), issue.Key)
	}

	return issuesURL
}
