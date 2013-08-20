#-- encoding: UTF-8
#-- copyright
# OpenProject is a project management system.
#
# Copyright (C) 2012-2013 the OpenProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See doc/COPYRIGHT.rdoc for more details.
#++
require File.expand_path('../../test_helper', __FILE__)

class IssueTest < ActiveSupport::TestCase
  include MiniTest::Assertions # refute

  fixtures :all

  def test_create
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 3,
                             :status_id => 1,
                             :priority => IssuePriority.all.first,
                             :subject => 'test_create',
                             :description => 'IssueTest#test_create',
                             :estimated_hours => '1:30' }
    end
    assert issue.save
    issue.reload
    assert_equal 1.5, issue.estimated_hours
  end

  def test_create_minimal
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 3,
                             :status_id => 1,
                             :priority => IssuePriority.all.first,
                             :subject => 'test_create' }
    end
    assert issue.save
    assert issue.description.nil?
  end

  def test_create_with_required_custom_field
    field = WorkPackageCustomField.find_by_name('Database')
    field.update_attribute(:is_required, true)

    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :subject => 'test_create',
                             :description => 'IssueTest#test_create_with_required_custom_field' }
    end
    assert issue.available_custom_fields.include?(field)
    # No value for the custom field
    assert !issue.save
    assert_include issue.errors[:custom_values], I18n.translate('activerecord.errors.messages.invalid')
    # Blank value
    issue.custom_field_values = { field.id => '' }
    assert !issue.save
    assert_include issue.errors[:custom_values], I18n.translate('activerecord.errors.messages.invalid')
    # Invalid value
    issue.custom_field_values = { field.id => 'SQLServer' }
    assert !issue.save
    assert_include issue.errors[:custom_values], I18n.translate('activerecord.errors.messages.invalid')
    # Valid value
    issue.custom_field_values = { field.id => 'PostgreSQL' }
    assert issue.save
    issue.reload
    assert_equal 'PostgreSQL', issue.custom_value_for(field).value
  end

  def test_visible_scope_for_anonymous
    # Anonymous user should see issues of public projects only
    issues = Issue.visible(User.anonymous).all
    assert issues.any?
    assert_nil issues.detect {|issue| !issue.project.is_public?}
    # Anonymous user should not see work units without permission
    Role.anonymous.remove_permission!(:view_work_packages)
    issues = Issue.visible(User.anonymous).all
    assert issues.empty?
  end

  def test_visible_scope_for_user
    user = User.find(9)
    assert user.projects.empty?
    # Non member user should see issues of public projects only
    issues = Issue.visible(user).all
    assert issues.any?
    assert_nil issues.detect {|issue| !issue.project.is_public?}
    # Non member user should not see issues without permission
    Role.non_member.remove_permission!(:view_work_packages)
    user.reload
    issues = Issue.visible(user).all
    assert issues.empty?
    # User should see issues of projects for which he has view_issues permissions only
    Member.new.tap do |m|
      m.force_attributes = { :principal => user, :project_id => 2, :role_ids => [1] }
    end.save!
    user.reload
    issues = Issue.visible(user).all
    assert issues.any?
    assert_nil issues.detect {|issue| issue.project_id != 2}
  end

  def test_visible_scope_for_admin
    user = User.find(1)
    user.members.each(&:destroy)
    assert user.projects.empty?
    issues = Issue.visible(user).all
    assert issues.any?
    # Admin should see issues on private projects that he does not belong to
    assert issues.detect {|issue| !issue.project.is_public?}
  end

  def test_errors_full_messages_should_include_custom_fields_errors
    field = WorkPackageCustomField.find_by_name('Database')

    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :subject => 'test_create',
                             :description => 'IssueTest#test_create_with_required_custom_field' }
    end
    assert issue.available_custom_fields.include?(field)
    # Invalid value
    issue.custom_field_values = { field.id => 'SQLServer' }

    assert !issue.valid?
    assert_equal 1, issue.errors.full_messages.size
    assert_equal "Database is not included in the list", issue.errors.full_messages.first
  end

  def test_update_issue_with_required_custom_field
    field = WorkPackageCustomField.find_by_name('Database')
    field.update_attribute(:is_required, true)

    CustomValue.delete 18

    issue = Issue.find(1)
    assert_nil issue.custom_value_for(field)
    assert issue.available_custom_fields.include?(field)
    # No change to custom values, issue can be saved
    assert issue.save
    # Blank value
    issue.custom_field_values = { field.id => '' }
    assert !issue.save
    # Valid value
    issue.custom_field_values = { field.id => 'PostgreSQL' }
    assert issue.save
    issue.reload
    assert_equal 'PostgreSQL', issue.custom_value_for(field).value
  end

  def test_should_not_update_attributes_if_custom_fields_validation_fails
    issue = Issue.find(1)
    field = WorkPackageCustomField.find_by_name('Database')
    assert issue.available_custom_fields.include?(field)

    issue.custom_field_values = { field.id => 'Invalid' }
    issue.subject = 'Should be not be saved'
    assert !issue.save

    issue.reload
    assert_equal "Can't print recipes", issue.subject
  end

  def test_should_not_recreate_custom_values_objects_on_update
    field = WorkPackageCustomField.find_by_name('Database')

    issue = Issue.find(1)
    issue.custom_field_values = { field.id => 'PostgreSQL' }
    assert issue.save
    custom_value = issue.custom_value_for(field)
    issue.reload
    issue.custom_field_values = { field.id => 'MySQL' }
    assert issue.save
    issue.reload
    assert_equal custom_value.id, issue.custom_value_for(field).id
  end

  def test_should_not_update_custom_fields_on_changing_type_with_different_custom_fields
    issue = Issue.new(:project => Project.find(1))
    issue.force_attributes = {:type_id => 1, :author_id => 1, :status_id => 1, :subject => 'Test', :custom_field_values => {'2' => 'Test'}}
    issue.save!

    assert !Type.find(2).custom_field_ids.include?(2)

    issue = Issue.find(issue.id)
    issue.attributes = {:type_id => 2, :custom_field_values => {'1' => ''}}

    issue = Issue.find(issue.id)
    custom_value = issue.custom_value_for(2)
    assert_not_nil custom_value
    assert_equal 'Test', custom_value.value
  end

  def test_assigning_type_id_should_reload_custom_fields_values
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project => Project.find(1) }
    end
    assert issue.custom_field_values.empty?
    issue.type_id = 1
    assert issue.custom_field_values.any?
  end

  def test_assigning_attributes_should_assign_type_id_first
    attributes = ActiveSupport::OrderedHash.new
    attributes['custom_field_values'] = { '1' => 'MySQL' }
    attributes['type_id'] = '1'
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project => Project.find(1) }
    end
    issue.attributes = attributes
    assert_not_nil issue.custom_value_for(1)
    assert_equal 'MySQL', issue.custom_value_for(1).value
  end

  def test_should_update_issue_with_disabled_type
    p = Project.find(1)
    issue = Issue.find(1)

    p.types.delete(issue.type)
    assert !p.types.include?(issue.type)

    issue.reload
    issue.subject = 'New subject'
    assert issue.save
  end

  def test_should_not_set_a_disabled_type
    p = Project.find(1)
    p.types.delete(Type.find(2))

    issue = Issue.find(1)
    issue.type_id = 2
    issue.subject = 'New subject'
    assert !issue.save
    refute_empty issue.errors[:type_id]
  end

  def test_category_based_assignment
    (issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 3,
                             :status_id => 1,
                             :priority => IssuePriority.all.first,
                             :subject => 'Assignment test',
                             :description => 'Assignment test',
                             :category_id => 1 }
    end).save!
    assert_equal IssueCategory.find(1).assigned_to, issue.assigned_to
  end

  def test_copy
    issue = Issue.new.copy_from(1)
    assert issue.save
    issue.reload
    orig = Issue.find(1)
    assert_equal orig.subject, issue.subject
    assert_equal orig.type, issue.type
    assert_equal "125", issue.custom_value_for(2).value
  end

  def test_copy_should_copy_status
    orig = Issue.find(8)
    assert orig.status != IssueStatus.default

    issue = Issue.new.copy_from(orig)
    assert issue.save
    issue.reload
    assert_equal orig.status, issue.status
  end

  def test_should_close_duplicates
    # Create 3 issues
    issue1 = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :priority => IssuePriority.all.first,
                             :subject => 'Duplicates test',
                             :description => 'Duplicates test' }
    end
    assert issue1.save
    issue2 = Issue.new.copy_from(issue1)
    assert issue2.save
    issue3 = Issue.new.copy_from(issue1)
    assert issue3.save

    # 2 is a dupe of 1
    IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => issue2,
                             :issue_to => issue1,
                             :relation_type => IssueRelation::TYPE_DUPLICATES }
    end.save!
    # And 3 is a dupe of 2
    IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => issue3,
                             :issue_to => issue2,
                             :relation_type => IssueRelation::TYPE_DUPLICATES }
    end.save!
    # And 3 is a dupe of 1 (circular duplicates)
    IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => issue3,
                             :issue_to => issue1,
                             :relation_type => IssueRelation::TYPE_DUPLICATES }
    end.save!

    assert issue1.reload.duplicates.include?(issue2)

    # Closing issue 1
    issue1.add_journal(User.find(:first), "Closing issue1")
    issue1.status = IssueStatus.find :first, :conditions => {:is_closed => true}
    assert issue1.save
    # 2 and 3 should be also closed
    assert issue2.reload.closed?
    assert issue3.reload.closed?
  end

  def test_should_not_close_duplicated_issue
    # Create 3 issues
    issue1 = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :priority => IssuePriority.all.first,
                             :subject => 'Duplicates test',
                             :description => 'Duplicates test' }
    end

    assert issue1.save
    issue2 = Issue.new.copy_from(issue1)
    assert issue2.save

    # 2 is a dupe of 1
    IssueRelation.new.force_attributes = {:issue_from => issue2, :issue_to => issue1, :relation_type => IssueRelation::TYPE_DUPLICATES}
    # 2 is a dup of 1 but 1 is not a duplicate of 2
    assert !issue2.reload.duplicates.include?(issue1)

    # Closing issue 2
    issue2.add_journal(User.find(:first), "Closing issue2")
    issue2.status = IssueStatus.find :first, :conditions => {:is_closed => true}
    assert issue2.save
    # 1 should not be also closed
    assert !issue1.reload.closed?
  end

  def test_assignable_versions
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :fixed_version_id => 1,
                             :subject => 'New issue' }
    end
    assert_equal ['open'], issue.assignable_versions.collect(&:status).uniq
  end

  def test_should_not_be_able_to_assign_a_new_issue_to_a_closed_version
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :fixed_version_id => 1,
                             :subject => 'New issue' }
    end

    assert !issue.save
    refute_empty issue.errors[:fixed_version_id]
  end

  def test_should_not_be_able_to_assign_a_new_issue_to_a_locked_version
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :fixed_version_id => 2,
                             :subject => 'New issue' }
    end
    assert !issue.save
    refute_empty issue.errors[:fixed_version_id]
  end

  def test_should_be_able_to_assign_a_new_issue_to_an_open_version
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :fixed_version_id => 3,
                             :subject => 'New issue' }
    end
    assert issue.save
  end

  def test_should_be_able_to_update_an_issue_assigned_to_a_closed_version
    issue = Issue.find(11)
    assert_equal 'closed', issue.fixed_version.status
    issue.subject = 'Subject changed'
    assert issue.save
  end

  def test_should_not_be_able_to_reopen_an_issue_assigned_to_a_closed_version
    issue = Issue.find(11)
    issue.status_id = 1
    assert !issue.save
    refute_empty issue.errors[:base]
  end

  def test_should_be_able_to_reopen_and_reassign_an_issue_assigned_to_a_closed_version
    issue = Issue.find(11)
    issue.status_id = 1
    issue.fixed_version_id = 3
    assert issue.save
  end

  def test_should_be_able_to_reopen_an_issue_assigned_to_a_locked_version
    issue = Issue.find(12)
    assert_equal 'locked', issue.fixed_version.status
    issue.status_id = 1
    assert issue.save
  end

  def test_move_to_another_project_with_same_category
    issue = Issue.find(1)
    assert issue.move_to_project(Project.find(2))
    issue.reload
    assert_equal 2, issue.project_id
    # Category changes
    assert_equal 4, issue.category_id
    # Make sure time entries were move to the target project
    assert_equal 2, issue.time_entries.first.project_id
  end

  def test_move_to_another_project_without_same_category
    issue = Issue.find(2)
    assert issue.move_to_project(Project.find(2))
    issue.reload
    assert_equal 2, issue.project_id
    # Category cleared
    assert_nil issue.category_id
  end

  def test_move_to_another_project_should_clear_fixed_version_when_not_shared
    issue = Issue.find(1)
    issue.update_attribute(:fixed_version_id, 1)
    issue.reload
    assert issue.move_to_project(Project.find(2))
    issue.reload
    assert_equal 2, issue.project_id
    # Cleared fixed_version
    assert_equal nil, issue.fixed_version
  end

  def test_move_to_another_project_should_keep_fixed_version_when_shared_with_the_target_project
    issue = Issue.find(1)
    issue.update_attribute(:fixed_version_id, 4)
    issue.reload
    assert issue.move_to_project(Project.find(5))
    issue.reload
    assert_equal 5, issue.project_id
    # Keep fixed_version
    assert_equal 4, issue.fixed_version_id
  end

  def test_move_to_another_project_should_clear_fixed_version_when_not_shared_with_the_target_project
    issue = Issue.find(1)
    issue.update_attribute(:fixed_version_id, 1)
    issue.reload
    assert issue.move_to_project(Project.find(5))
    issue.reload
    assert_equal 5, issue.project_id
    # Cleared fixed_version
    assert_equal nil, issue.fixed_version
  end

  def test_move_to_another_project_should_keep_fixed_version_when_shared_systemwide
    issue = Issue.find(1)
    issue.update_attribute(:fixed_version_id, 7)
    issue.reload
    assert issue.move_to_project(Project.find(2))
    issue.reload
    assert_equal 2, issue.project_id
    # Keep fixed_version
    assert_equal 7, issue.fixed_version_id
  end

  def test_move_to_another_project_with_disabled_type
    issue = Issue.find(1)
    target = Project.find(2)
    target.type_ids = [3]
    target.save
    assert_equal false, issue.move_to_project(target)
    issue.reload
    assert_equal 1, issue.project_id
  end

  def test_copy_to_the_same_project
    issue = Issue.find(1)
    copy = nil
    assert_difference 'Issue.count' do
      copy = issue.move_to_project(issue.project, nil, :copy => true)
    end
    assert_kind_of Issue, copy
    assert_equal issue.project, copy.project
    assert_equal "125", copy.custom_value_for(2).value
  end

  def test_copy_to_another_project_and_type
    issue = Issue.find(1)
    copy = nil
    assert_difference 'Issue.count' do
      copy = issue.move_to_project(Project.find(3), Type.find(2), :copy => true)
    end
    copy.reload
    assert_kind_of Issue, copy
    assert_equal Project.find(3), copy.project
    assert_equal Type.find(2), copy.type
    # Custom field #2 is not associated with target type
    assert_nil copy.custom_value_for(2)
  end

  context "#move_to_project" do
    context "as a copy" do
      setup do
        @issue = Issue.find(1)
        @copy = nil
      end

      should "allow assigned_to changes" do
        @copy = @issue.move_to_project(Project.find(3), Type.find(2), {:copy => true, :attributes => {:assigned_to_id => 3}})
        assert_equal 3, @copy.assigned_to_id
      end

      should "allow status changes" do
        @copy = @issue.move_to_project(Project.find(3), Type.find(2), {:copy => true, :attributes => {:status_id => 2}})
        assert_equal 2, @copy.status_id
      end

      should "allow start date changes" do
        date = Date.today
        @copy = @issue.move_to_project(Project.find(3), Type.find(2), {:copy => true, :attributes => {:start_date => date}})
        assert_equal date, @copy.start_date
      end

      should "allow due date changes" do
        date = Date.today
        @copy = @issue.move_to_project(Project.find(3), Type.find(2), {:copy => true, :attributes => {:due_date => date}})

        assert_equal date, @copy.due_date
      end
    end
  end

  def test_recipients_should_not_include_users_that_cannot_view_the_issue
    issue = Issue.find(12)
    assert issue.recipients.include?(issue.author.mail)
    User.current = issue.author
    # move the issue to a private project
    copy  = issue.move_to_project(Project.find(5), Type.find(2), :copy => true)
    # the author of the original issue is no user of the project and thus not informed
    assert !copy.recipients.include?(copy.author.mail)
  end

  def test_watcher_recipients_should_not_include_users_that_cannot_view_the_issue
    issue = FactoryGirl.create :issue
    user = FactoryGirl.create :user, :member_in_project => issue.project
    Watcher.create!(:user => user, :watchable => issue)
    issue.project.members.first.roles.first.remove_permission! :view_work_packages
    issue.reload
    assert issue.watched_by?(user)
    assert !issue.watcher_recipients.include?(user.mail)
  end

  def test_issue_destroy
    Issue.find(1).destroy
    assert_nil Issue.find_by_id(1)
    assert_nil TimeEntry.find_by_work_package_id(1)
  end

  def test_blocked
    blocked_issue = Issue.find(9)
    blocking_issue = Issue.find(10)

    assert blocked_issue.blocked?
    assert !blocking_issue.blocked?
  end

  def test_blocked_issues_dont_allow_closed_statuses
    blocked_issue = Issue.find(9)

    allowed_statuses = blocked_issue.new_statuses_allowed_to(users(:users_002))
    assert !allowed_statuses.empty?
    closed_statuses = allowed_statuses.select {|st| st.is_closed?}
    assert closed_statuses.empty?
  end

  def test_unblocked_issues_allow_closed_statuses
    blocking_issue = Issue.find(10)

    allowed_statuses = blocking_issue.new_statuses_allowed_to(users(:users_002))
    assert !allowed_statuses.empty?
    closed_statuses = allowed_statuses.select {|st| st.is_closed?}
    assert !closed_statuses.empty?
  end

  def test_rescheduling_an_issue_should_reschedule_following_issue
    (issue1 = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :subject => '-',
                             :start_date => Date.today,
                             :due_date => Date.today + 2 }
    end).save!
    (issue2 = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 1,
                             :status_id => 1,
                             :subject => '-',
                             :start_date => Date.today,
                             :due_date => Date.today + 2 }
    end).save!
    IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => issue1,
                             :issue_to => issue2,
                             :relation_type => IssueRelation::TYPE_PRECEDES }
    end.save!
    assert_equal issue1.due_date + 1, issue2.reload.start_date

    issue1.due_date = Date.today + 5
    issue1.save!
    assert_equal issue1.due_date + 1, issue2.reload.start_date
  end

  def test_overdue
    assert Issue.new(:due_date => 1.day.ago.to_date).overdue?
    assert !Issue.new(:due_date => Date.today).overdue?
    assert !Issue.new(:due_date => 1.day.from_now.to_date).overdue?
    assert !Issue.new(:due_date => nil).overdue?
    assert !Issue.new(:due_date => 1.day.ago.to_date, :status => IssueStatus.find(:first, :conditions => {:is_closed => true})).overdue?
  end

  context "#behind_schedule?" do
    should "be false if the issue has no start_date" do
      assert !Issue.new(:start_date => nil, :due_date => 1.day.from_now.to_date, :done_ratio => 0).behind_schedule?
    end

    should "be false if the issue has no due_date" do
      assert !Issue.new(:start_date => 1.day.from_now.to_date, :due_date => nil, :done_ratio => 0).behind_schedule?
    end

    should "be false if the issue has more done than it's calendar time" do
      assert !Issue.new(:start_date => 50.days.ago.to_date, :due_date => 50.days.from_now.to_date, :done_ratio => 90).behind_schedule?
    end

    should "be true if the issue hasn't been started at all" do
      assert Issue.new(:start_date => 1.day.ago.to_date, :due_date => 1.day.from_now.to_date, :done_ratio => 0).behind_schedule?
    end

    should "be true if the issue has used more calendar time than it's done ratio" do
      assert Issue.new(:start_date => 100.days.ago.to_date, :due_date => Date.today, :done_ratio => 90).behind_schedule?
    end
  end

  context "#assignable_users" do
    should "be Users" do
      assert_kind_of User, Issue.find(1).assignable_users.first
    end

    should "not show the issue author twice" do
      assignable_user_ids = Issue.find(1).assignable_users.collect(&:id)
      assert_equal 2, assignable_user_ids.length

      assignable_user_ids.each do |user_id|
        assert_equal 1, assignable_user_ids.select {|i| i == user_id}.length, "User #{user_id} appears more or less than once"
      end
    end
  end

  def test_create_should_send_email_notification
    ActionMailer::Base.deliveries.clear
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 3,
                             :status_id => 1,
                             :priority => IssuePriority.all.first,
                             :subject => 'test_create',
                             :estimated_hours => '1:30' }
    end

    assert issue.save
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_stale_issue_should_not_send_email_notification
    ActionMailer::Base.deliveries.clear
    i = FactoryGirl.create :issue
    i.add_journal(User.find(1))

    issue = Issue.find(i.id)
    stale = Issue.find(i.id)

    issue.subject = 'Subjet update'
    assert issue.save
    assert_equal 2, ActionMailer::Base.deliveries.size
    ActionMailer::Base.deliveries.clear

    stale.add_journal(User.find(1))
    stale.subject = 'Another subjet update'
    assert_raise ActiveRecord::StaleObjectError do
      stale.save
    end
    assert ActionMailer::Base.deliveries.empty?
  end

  def test_journalized_description
    WorkPackageCustomField.delete_all

    i = Issue.first
    i.recreate_initial_journal!
    i.reload
    old_description = i.description
    new_description = "This is the new description"

    i.add_journal(User.find(2))
    i.description = new_description
    assert_difference 'Journal.count', 1 do
      i.save!
    end

    journal = Journal.first(:order => 'id DESC')
    assert_equal i, journal.journable
    assert journal.changed_data.has_key? :description
    assert_equal old_description, journal.old_value_for("description")
    assert_equal new_description, journal.new_value_for("description")
  end

  def test_all_dependent_issues
    IssueRelation.delete_all
    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(1),
                             :issue_to => Issue.find(2),
                             :relation_type => IssueRelation::TYPE_PRECEDES }
    end
    assert relation.save

    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(2),
                             :issue_to => Issue.find(3),
                             :relation_type => IssueRelation::TYPE_PRECEDES }
    end
    assert relation.save

    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(3),
                             :issue_to => Issue.find(8),
                             :relation_type => IssueRelation::TYPE_PRECEDES }
    end
    assert relation.save

    assert_equal [2, 3, 8], Issue.find(1).all_dependent_issues.collect(&:id).sort
  end

  def test_all_dependent_issues_with_persistent_circular_dependency
    IssueRelation.delete_all
    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(1),
                             :issue_to => Issue.find(2),
                             :relation_type => IssueRelation::TYPE_PRECEDES }
    end
    assert relation.save
    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(2),
                             :issue_to => Issue.find(3),
                             :relation_type => IssueRelation::TYPE_PRECEDES }
    end
    assert relation.save
    # Validation skipping
    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(3),
                             :issue_to => Issue.find(1),
                             :relation_type => IssueRelation::TYPE_PRECEDES }
    end
    assert relation.save(:validate => false)

    assert_equal [2, 3], Issue.find(1).all_dependent_issues.collect(&:id).sort
  end

  def test_all_dependent_issues_with_persistent_multiple_circular_dependencies
    IssueRelation.delete_all
    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(1),
                             :issue_to => Issue.find(2),
                             :relation_type => IssueRelation::TYPE_RELATES }
    end
    assert relation.save

    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(2),
                             :issue_to => Issue.find(3),
                             :relation_type => IssueRelation::TYPE_RELATES }
    end
    assert relation.save

    relation = IssueRelation.new.tap do |i|
      i.force_attributes = { :issue_from => Issue.find(3),
                             :issue_to => Issue.find(8),
                             :relation_type => IssueRelation::TYPE_RELATES }
    end
    assert relation.save

    # Validation skipping
    relation = IssueRelation.new.tap do |i|
      i. force_attributes = { :issue_from => Issue.find(8),
                              :issue_to => Issue.find(2),
                              :relation_type => IssueRelation::TYPE_RELATES }
    end
    assert relation.save(:validate => false)

    relation = IssueRelation.new.tap do |i|
      i. force_attributes = { :issue_from => Issue.find(3),
                              :issue_to => Issue.find(1),
                              :relation_type => IssueRelation::TYPE_RELATES }
    end
    assert relation.save(:validate => false)

    assert_equal [2, 3, 8], Issue.find(1).all_dependent_issues.collect(&:id).sort
  end

  context "#done_ratio" do
    setup do
      @issue = Issue.find(1)
      @issue_status = IssueStatus.find(1)
      @issue_status.update_attribute(:default_done_ratio, 50)
      @issue2 = Issue.find(2)
      @issue_status2 = IssueStatus.find(2)
      @issue_status2.update_attribute(:default_done_ratio, 0)
    end

    context "with Setting.issue_done_ratio using the issue_field" do
      setup do
        Setting.issue_done_ratio = 'issue_field'
      end

      should "read the issue's field" do
        assert_equal 0, @issue.done_ratio
        assert_equal 30, @issue2.done_ratio
      end
    end

    context "with Setting.issue_done_ratio using the issue_status" do
      setup do
        Setting.issue_done_ratio = 'issue_status'
      end

      should "read the Issue Status's default done ratio" do
        assert_equal 50, @issue.done_ratio
        assert_equal 0, @issue2.done_ratio
      end
    end
  end

  context "#update_done_ratio_from_issue_status" do
    setup do
      @issue = Issue.find(1)
      @issue_status = IssueStatus.find(1)
      @issue_status.update_attribute(:default_done_ratio, 50)
      @issue2 = Issue.find(2)
      @issue_status2 = IssueStatus.find(2)
      @issue_status2.update_attribute(:default_done_ratio, 0)
    end

    context "with Setting.issue_done_ratio using the issue_field" do
      setup do
        Setting.issue_done_ratio = 'issue_field'
      end

      should "not change the issue" do
        @issue.update_done_ratio_from_issue_status
        @issue2.update_done_ratio_from_issue_status

        assert_equal 0, @issue.read_attribute(:done_ratio)
        assert_equal 30, @issue2.read_attribute(:done_ratio)
      end
    end

    context "with Setting.issue_done_ratio using the issue_status" do
      setup do
        Setting.issue_done_ratio = 'issue_status'
      end

      should "change the issue's done ratio" do
        @issue.update_done_ratio_from_issue_status
        @issue2.update_done_ratio_from_issue_status

        assert_equal 50, @issue.read_attribute(:done_ratio)
        assert_equal 0, @issue2.read_attribute(:done_ratio)
      end
    end
  end

  test "#by_type" do
    groups = Issue.by_type(Project.find(1))
    assert_equal 3, groups.size
    assert_equal 7, groups.inject(0) {|sum, group| sum + group['total'].to_i}
  end

  test "#by_version" do
    groups = Issue.by_version(Project.find(1))
    assert_equal 3, groups.size
    assert_equal 3, groups.inject(0) {|sum, group| sum + group['total'].to_i}
  end

  test "#by_priority" do
    groups = Issue.by_priority(Project.find(1))
    assert_equal 4, groups.size
    assert_equal 7, groups.inject(0) {|sum, group| sum + group['total'].to_i}
  end

  test "#by_category" do
    groups = Issue.by_category(Project.find(1))
    assert_equal 2, groups.size
    assert_equal 3, groups.inject(0) {|sum, group| sum + group['total'].to_i}
  end

  test "#by_assigned_to" do
    groups = Issue.by_assigned_to(Project.find(1))
    assert_equal 2, groups.size
    assert_equal 2, groups.inject(0) {|sum, group| sum + group['total'].to_i}
  end

  test "#by_author" do
    groups = Issue.by_author(Project.find(1))
    assert_equal 4, groups.size
    assert_equal 7, groups.inject(0) {|sum, group| sum + group['total'].to_i}
  end

  test "#by_subproject" do
    groups = Issue.by_subproject(Project.find(1))
    assert_equal 2, groups.size
    assert_equal 5, groups.inject(0) {|sum, group| sum + group['total'].to_i}
  end

  def test_recently_updated_with_limit_scopes
    #should return the last updated issue
    assert_equal 1, Issue.recently_updated.with_limit(1).length
    assert_equal Issue.find(:first, :order => "updated_at DESC"), Issue.recently_updated.with_limit(1).first
  end

  def test_on_active_projects_scope
    assert Project.find(2).archive

    before = Issue.on_active_project.length
    # test inclusion to results
    issue = Issue.generate_for_project!(Project.find(1), :type => Project.find(2).types.first)
    assert_equal before + 1, Issue.on_active_project.length

    # Move to an archived project
    issue.project = Project.find(2)
    assert issue.save
    assert_equal before, Issue.on_active_project.length
  end

  context "Issue#recipients" do
    setup do
      @project = Project.find(1)
      @author = User.generate_with_protected!
      @assignee = User.generate_with_protected!
      @issue = Issue.generate_for_project!(@project, :assigned_to => @assignee, :author => @author)
    end

    should "include project recipients" do
      assert @project.recipients.present?
      @project.recipients.each do |project_recipient|
        assert @issue.recipients.include?(project_recipient)
      end
    end

    should "include the author if the author is active" do
      assert @issue.author, "No author set for Issue"
      assert @issue.recipients.include?(@issue.author.mail)
    end

    should "include the assigned to user if the assigned to user is active" do
      assert @issue.assigned_to, "No assigned_to set for Issue"
      assert @issue.recipients.include?(@issue.assigned_to.mail)
    end

    should "not include users who opt out of all email" do
      @author.update_attribute(:mail_notification, :none)

      assert !@issue.recipients.include?(@issue.author.mail)
    end

    should "not include the issue author if they are only notified of assigned issues" do
      @author.update_attribute(:mail_notification, :only_assigned)

      assert !@issue.recipients.include?(@issue.author.mail)
    end

    should "not include the assigned user if they are only notified of owned issues" do
      @assignee.update_attribute(:mail_notification, :only_owner)

      assert !@issue.recipients.include?(@issue.assigned_to.mail)
    end

  end

  def test_create_should_not_send_email_notification_if_told_not_to
    ActionMailer::Base.deliveries.clear
    issue = Issue.new.tap do |i|
      i.force_attributes = { :project_id => 1,
                             :type_id => 1,
                             :author_id => 3,
                             :status_id => 1,
                             :priority => IssuePriority.first,
                             :subject => 'test_create',
                             :estimated_hours => '1:30' }
    end
    IssueObserver.instance.send_notification = false

    assert issue.save
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  test 'changing the line endings in a description will not be recorded as a Journal' do
    User.current = User.find(1)
    issue = Issue.find(1)
    issue.update_attribute(:description, "Description with newlines\n\nembedded")
    issue.reload
    assert issue.description.include?("\n")

    assert_no_difference("Journal.count") do
      issue.safe_attributes= {
        'description' => "Description with newlines\r\n\r\nembedded"
      }
      assert issue.save
    end

    assert_equal "Description with newlines\n\nembedded", issue.reload.description
  end

end
