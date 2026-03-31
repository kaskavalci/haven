require "application_system_test_case"
require_relative 'systemtest_helpers.rb'

class DraftPersistenceTest < ApplicationSystemTestCase
  test_users = {
    jackson: {email: "andrew@jackson.com", pass: "jacksonpass"}
  }

  test "new post draft survives navigation" do
    log_in_with test_users[:jackson]
    page.execute_script("localStorage.clear()")

    click_on "New Post Button"
    draft_content = "#{rand} Draft that should persist"
    fill_in "post_content", with: draft_content
    sleep 1

    stored = page.evaluate_script("localStorage.getItem('haven_draft_new')")
    assert_equal draft_content, stored

    click_on "Home"
    click_on "New Post Button"

    assert_equal draft_content, find_field("post_content").value
    assert_text "Draft restored"

    page.execute_script("localStorage.clear()")
    click_on "Logout"
  end

  test "draft is cleared after successful save" do
    log_in_with test_users[:jackson]
    page.execute_script("localStorage.clear()")

    click_on "New Post Button"
    draft_content = "#{rand} This will be saved properly"
    fill_in "post_content", with: draft_content
    sleep 1

    click_on "Save Post"
    assert_text draft_content

    click_on "Home"
    click_on "New Post Button"

    assert_equal "", find_field("post_content").value
    stored = page.evaluate_script("localStorage.getItem('haven_draft_new')")
    assert_nil stored

    page.execute_script("localStorage.clear()")
    click_on "Logout"
  end

  test "edit post draft survives navigation" do
    log_in_with test_users[:jackson]
    page.execute_script("localStorage.clear()")

    click_on "New Post Button"
    original_content = "#{rand} Original post content"
    fill_in "post_content", with: original_content
    click_on "Save Post"
    assert_text original_content
    post_url = current_url

    click_on "Edit"
    modified_content = "#{rand} Modified but not saved"
    fill_in "post_content", with: modified_content
    sleep 1

    click_on "Home"

    visit post_url
    click_on "Edit"

    assert_equal modified_content, find_field("post_content").value
    assert_text "Draft restored"

    page.execute_script("localStorage.clear()")
    click_on "Logout"
  end

  test "discard draft restores server content" do
    log_in_with test_users[:jackson]
    page.execute_script("localStorage.clear()")

    click_on "New Post Button"
    draft_content = "#{rand} Draft to be discarded"
    fill_in "post_content", with: draft_content
    sleep 1

    click_on "Home"
    click_on "New Post Button"

    assert_equal draft_content, find_field("post_content").value
    assert_text "Draft restored"

    click_on "Discard"

    assert_equal "", find_field("post_content").value
    stored = page.evaluate_script("localStorage.getItem('haven_draft_new')")
    assert_nil stored
    assert_no_text "Draft restored"

    page.execute_script("localStorage.clear()")
    click_on "Logout"
  end
end
