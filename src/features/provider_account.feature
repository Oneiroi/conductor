Feature: Manage Provider Accounts
  In order to manage my cloud infrastructure
  As a user
  I want to manage provider accounts

  Background:
    Given I am an authorised user
    And I am logged in
    And I am using new UI

  Scenario: List provider accounts
    Given I am on the homepage
    And there is a provider named "testprovider"
    When I go to the admin provider accounts page
    Then I should see "New Account"
    And there should be no provider accounts

  Scenario: Create a new Provider Account
    Given there is a provider named "testprovider"
    And there are no provider accounts
    And I am on the admin provider accounts page
    When I follow "New Account"
    Then I should be on the new admin provider account page
    And I should see "New Account"
    When I select "testprovider" from "provider_id"
    And I fill in "cloud_account[label]" with "testaccount"
    And I fill in "cloud_account[username]" with "mockuser"
    And I fill in "cloud_account[password]" with "mockpassword"
    And I fill in "quota[maximum_running_instances]" with "13"
    And I fill in "cloud_account[account_number]" with "222222"
    And I attach the "private.key" file to "cloud_account[x509_cert_priv_file]"
    And I attach the "public.key" file to "cloud_account[x509_cert_pub_file]"
    And I press "Add"
    Then I should be on testaccount's provider account page
    And I should see "Provider account added"
    And I should have a provider account named "testaccount"
    And I should see "Properties for testaccount"
    And I should see "Running instances quota: 13"
    And I should see "Account ID: 222222"

  Scenario: Test Provider Account Connection Successful
    Given there is a provider named "testprovider"
    And there are no provider accounts
    And I am on the admin provider accounts page
    When I follow "New Account"
    Then I should be on the new admin provider account page
    When I fill in "cloud_account[username]" with "mockuser"
    And I fill in "cloud_account[password]" with "mockpassword"
    And I press "Test Account"
    Then I should see "Test Connection Success"

  Scenario: Test Provider Account Connection Failure
    Given there is a provider named "testprovider"
    And there are no provider accounts
    And I am on the admin provider accounts page
    When I follow "New Account"
    Then I should be on the new admin provider account page
    When I fill in "cloud_account[username]" with "mockuser"
    And I fill in "cloud_account[password]" with "wrong password"
    And I press "Test Account"
    Then I should see "Test Connection Failed"

  Scenario: Delete a provider account
    Given there is a provider named "testprovider"
    And there is a provider account named "testaccount"
    And I am on the admin provider accounts page
    When I check the "testaccount" account
    And I press "Delete"
    Then I should be on the admin provider accounts page
    And there should be no provider accounts
