require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'password is valid' do
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :password => '123456', :password_confirmation => '654321') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :password => '123') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :password => '') }
    assert Factory(:user, :password => '123456')

    user = Factory(:user)
    user.password_required = false
    user.password = ''
    user.password_confirmation = ''
    assert user.save
  end

  test 'name is not empty' do
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :name => '') }
  end

  test 'email is not empty' do
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => '') }
  end

  test 'name is unique' do
    Factory(:user, :name => 'Test')
    assert User.exists?(:name => 'Test')
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :name => 'Test') }
  end

  test 'email is unique' do
    Factory(:user, :email => 'test@test.com')
    assert User.exists?(:email => 'test@test.com')
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => 'test@test.com') }
  end

  test 'email is valid' do
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => '@.com') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => '@test.com') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => 'test@.com') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => 'test@test.') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => 'test@$%^.com') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => 'test@test.c') }
    assert_raise(ActiveRecord::RecordInvalid) { Factory(:user, :email => 'test@test.$$$') }
  end

  test 'reset_password_token gets cleared' do
    token = SecureRandom.base64(32)
    user = Factory(:user, :reset_password_token => token, :dont_clear_reset_password_token => true)
    assert_equal user.reset_password_token, token

    user2 = User.find_by_reset_password_token(token)
    user2.save
    assert user2.reset_password_token.blank?
  end

  test 'root folder and admins group get created' do
    admin = Factory(:user, :is_admin => true)
    assert_equal Folder.where(:name => 'Root folder').count, 1
    assert_equal Group.where(:name => 'Admins').count, 1
    assert_equal admin.groups.count, 1
  end

  test 'cannot delete admin user' do
    admin = Factory(:user, :is_admin => true)
    normal_user = Factory(:user)

    assert_raise(RuntimeError) { admin.destroy }
    assert normal_user.destroy
  end

  test 'user permissions' do
    admin = Factory(:user, :is_admin => true)
    user = Factory(:user)
    root = Folder.root
    folder = Factory(:folder)
    group = Factory(:group)

    %w{create read update delete}.each { |method| assert admin.send("can_#{method}", root) }
    %w{create read update delete}.each { |method| assert admin.send("can_#{method}", folder) }
    %w{create read update delete}.each { |method| assert !user.send("can_#{method}", root) }
    %w{create read update delete}.each { |method| assert !user.send("can_#{method}", folder) }

    user.groups << group
    assert user.can_read(root)
    %w{create update delete}.each { |method| assert !user.send("can_#{method}", root) }
    %w{create read update delete}.each { |method| assert !user.send("can_#{method}", folder) }

    folder.permissions.where(:group_id => group).update_all(:can_create => true)
    assert user.can_create(folder)
    %w{read update delete}.each { |method| assert !user.send("can_#{method}", folder) }

    folder.permissions.where(:group_id => group).update_all(:can_read => true)
    %w{create read}.each { |method| assert user.send("can_#{method}", folder) }
    %w{update delete}.each { |method| assert !user.send("can_#{method}", folder) }

    folder.permissions.where(:group_id => group).update_all(:can_update => true)
    %w{create read update}.each { |method| assert user.send("can_#{method}", folder) }
    assert !user.can_delete(folder)

    folder.permissions.where(:group_id => group).update_all(:can_delete => true)
    %w{create read update delete}.each { |method| assert user.send("can_#{method}", folder) }

    assert user.can_read(root)
    %w{create update delete}.each { |method| assert !user.send("can_#{method}", root) }
    %w{create read update delete}.each { |method| assert admin.send("can_#{method}", root) }
    %w{create read update delete}.each { |method| assert admin.send("can_#{method}", folder) }
  end

  test 'hashed_password and password_salt do not change when leaving the password empty' do
    user = Factory(:user)
    assert !user.password_salt.blank?
    assert !user.hashed_password.blank?

    salt = user.password_salt
    hash = user.hashed_password

    user.password_required = false
    user.password = ''
    user.password_confirmation = ''

    assert user.save
    assert_equal user.password_salt, salt
    assert_equal user.hashed_password, hash
  end

  test 'hashed_password and password_salt change when updating the password' do
    user = Factory(:user)
    salt = user.password_salt
    hash = user.hashed_password

    user.password = 'test1234'
    user.password_confirmation = 'test1234'

    assert user.save
    assert_not_equal user.password_salt, salt
    assert_not_equal user.hashed_password, hash
    assert User.authenticate(user.name, 'test1234')
  end

  test 'whether a user is member of admins or not' do
    admin = Factory(:user, :is_admin => true)
    assert admin.member_of_admins?

    user = Factory(:user)
    assert !user.member_of_admins?

    user.groups << Group.find_by_name('Admins')
    assert user.member_of_admins?
  end

  test 'whether reset_password_token refreshes' do
    user = Factory(:user)
    assert user.reset_password_token.blank?

    user.refresh_reset_password_token
    assert !user.reset_password_token.blank?
    assert_in_delta user.reset_password_token_expires_at, 1.hour.from_now, 1.second

    token = user.reset_password_token
    expires_at = user.reset_password_token_expires_at
    user.refresh_reset_password_token

    assert !user.reset_password_token.blank?
    assert_not_equal user.reset_password_token, token
    assert_not_equal user.reset_password_token_expires_at, expires_at
  end

  test 'whether remember_token refreshes' do
    user = Factory(:user)
    assert user.remember_token.blank?

    user.refresh_remember_token
    assert !user.remember_token.blank?

    token = user.remember_token
    user.refresh_remember_token

    assert !user.remember_token.blank?
    assert_not_equal user.remember_token, token
  end

  test 'whether forget_me clears remember_token' do
    user = Factory(:user)
    user.refresh_remember_token
    assert !user.remember_token.blank?

    user.forget_me
    assert user.remember_token.blank?
    assert !user.changed? # There are no unsaved changes: `forget_me` saved the record
  end

  test 'authentication' do
    user = Factory(:user, :name => 'testname', :password => 'secret')
    assert !User.authenticate(nil, nil)
    assert !User.authenticate('', '')
    assert !User.authenticate('testname', nil)
    assert !User.authenticate('testname', '')
    assert !User.authenticate(nil, 'secret')
    assert !User.authenticate('', 'secret')
    assert !User.authenticate('test', 'test')
    assert User.authenticate('testname', 'secret')
  end

  test 'whether there is an admin user or not' do
    assert User.no_admin_yet?

    normal_user = Factory(:user)
    assert User.no_admin_yet?

    admin = Factory(:user, :is_admin => true)
    assert !User.no_admin_yet?
  end
end
