package Catalyst::Authentication::Store::Tangram;
use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Scalar::Util qw/blessed/;
use Catalyst::Authentication::Store::Tangram::User;

our $VERSION = '0.003';

BEGIN {
    __PACKAGE__->mk_accessors(qw/
        tangram_model 
        tangram_user_class 
        user_class 
        storage_method 
        use_roles
        role_relation
        role_name_field
    /);
}

sub _get_storage {
    my ($self, $c) = @_;
    $c->model($self->tangram_model)->${\$self->storage_method}();
}    

sub new {
    my ($class, $config, $app, $realm) = @_;
    die("tangram_user_class key must be defined in config")
        unless $config->{tangram_user_class};
    $config->{tangram_model} ||= 'Tangram';
    $config->{storage_method} ||= 'storage';
    $config->{user_class} ||= __PACKAGE__ . '::User';
    $config->{use_roles} ||= 0;
    $config->{use_roles} = 0 if $config->{use_roles} =~ /false/i;
    die("No role_relation config option set, cannot use roles") 
        if (!length($config->{role_relation}) && $config->{use_roles});
    die("No role_name_field config option set, cannot use roles")
        if (!length($config->{role_name_field}) && $config->{use_roles});
    bless { %$config }, $class;
}

sub find_user {
    my ($self, $authinfo, $c) = @_;
    my $tangram_class = $self->tangram_user_class;
    my $storage = $self->_get_storage($c);
    my $remote = $storage->remote($tangram_class);
    my $filter;
    foreach my $key (keys %$authinfo) {
        $filter = (defined $filter
            ? ($filter & $remote->{$key} eq $authinfo->{$key})
            : $remote->{$key} eq $authinfo->{$key}
        );
    }
    my @result = $storage->select($remote, filter => $filter);
    if (@result) {
        return $self->user_class->new($storage, $result[0], $self);
    }
    return;
}

sub for_session {
    my ($self, $user) = @_;
    return $user->id;
}

sub from_session {
    my ($self, $id) = @_;
    my $tangram_class = $self->tangram_user_class;
    my $tangram_user;
    eval { $tangram_user = $self->_get_storage->load($id) };
    return if $@ or !$tangram_user;
    return $self->user_class->new($self->_get_storage, $tangram_user, $self); # FIXME - $c arg for get_storage.
}

sub user_supports {
    my $class = shift;

    return Catalyst::Authentication::Store::Tangram::User->supports(@_);
}

sub lookup_roles {
    my ($self, $user_ob) = @_;
    return undef unless $self->use_roles;

    return map { $_->${\$self->role_name_field} }
        @{ $user_ob->_tangram->${\$self->role_relation}() };    
}

1;

=head1 NAME

Catalyst::Authentication::Store::Tangram - A storage class for Catalyst authentication from a class stored in Tangram

=head1 SYNOPSIS

    use Catalyst qw/
        Authentication
    /;

    __PACKAGE__->config( authentication => {  
        default_realm => 'members',
        realms => {
            members => {
                credential => {
                    class => 'Password',
                    password_field => 'password',
                    password_type => 'clear'
                },
                store => {
                    class => 'Tangram',
                    tangram_user_class => 'Users',
                    tangram_model => 'Tangram',
                    storage_method => 'storage', # $c->model('Tangram')->storage                
                },
            },
        },
    });

    # Log a user in:
    sub login : Global {
        my ( $self, $c ) = @_;

        $c->authenticate({  
            email_address => $c->req->param('email_address'),
            password => $c->req->param('password'),
        });
    }

=head1 DESCRIPTION 

The Catalyst::Authentication::Store::Tangram class provides access to authentication 
information stored in a database via L<Tangram>.

=head1 CONFIGURATION

The Tangram authentication store is activated by setting the store configuration class element 
to I<Tangram> as shown above. See the L<Catalyst::Plugin::Authentication> documentation 
for more details on configuring the store.

The Tangram storage module has several configuration options

    authentication => {  
        default_realm => 'members',
        realms => {
            members => {
                credential => {
                    # ...
                },
                store => {
                    class => 'Tangram',
                    user_class => 'Users',
                    tangram_model => 'Tangram',
                    storage_method => 'storage', # $c->model('Tangram')->storage                
                },
            },
        },
    }
    
=over

=item class

Class is part of the core L<Catalyst::Plugin::Authentication> module, it contains the class name of the store to be used.

=item tangram_user_class

Contains the class name of the class persisted in your Tangram schema to use as the source for user information. 
This config item is B<REQUIRED>. This class name is used to get a Tangram remote object when constructing a search
for your user when first authenticating, and also this is the class which the ->load method is called on to restore 
the user from a session.

=item tangram_model

Contains the class name (as passed to $c->model()) of the Tangram model to use as the source for user information. 
This config item is REQUIRED. The I<storage_method> method will be invoked on this class to get the L<Tangram::Storage>
instance to restore the user from.

=item storage_method

Contains the method to call on the I<tangram_model> to retrieve the instance of L<Tangram::Storage> which users are
looked up from.

=item user_class

Contains the class which the user object is blessed into. This class is usually L<Catalyst::Authentication::Store::Tangram::User>,
but you can sub-class that class and have your subclass used instead by setting this configuration parameter. You will not need to
use this setting unless you are doing unusual things with the user class.

=item use_roles

Activates role support if set to '1' 
 
=item role_relation

The name of the method to call on your Tangram user object to retrieve an array of roles for this user.

This field will probably be a L<Tangram::Type::Array::FromMany>, or a L<Tangram::Type::Array::FromOne>..

=item role_name_field

The name of the field to retrieve the name of the role from on the Tangram class representing roles.

=back

=head1 METHODS

=head2 new ( $config, $app, $realm )

Simple constructor, returns a blessed reference to the store object instance.

=head2 find_user ( $authinfo, $c )

I<$auth_info> is expected to be a hash with the keys being field names on your Tangram user object, and the values
being what those fields should be matched against. A tangram select will be built from the supplied authentication 
information, and this select is used to retrieve the user from Tangram.

=head2 for_session ( $c, $user )

This method returns the Tangram ID for the user, as that is all that is necessary to be persisted in the session
to restore the user.

=head2 from_session ( $c, $frozenuser )

This method is called whenever a user is being restored from the session. $frozenuser contains the Tangram ID of
the user to restore.

=head2 user_supports

Delegates to the L<Catalyst::Authentication::Store::Tangram::User->supports|Catalyst::Authentication::Store::Tangram::User#supports> 
method.

=head2 lookup_roles

Returns a list of roles that this user is authorised for.

=head1 SEE ALSO

L<Catalyst::Authentication::Store::Tangram::User>,
L<Catalyst::Plugin::Authentication>,
L<Catalyst::Authentication::Store>

=head1 AUTHOR

Tomas Doran, <bobtfish at bobtfish dot net>

With thanks to state51, my employer, for giving me the time to work on this.

=head1 BUGS

All complex software has bugs, and I'm sure that this module is no exception.

Please report bugs through the rt.cpan.org bug tracker.

=head1 COPYRIGHT

Copyright (c) 2008, state51. Some rights reserved.

=head1 LICENSE

This module is free software; you can use, redistribute, and modify it 
under the same terms as Perl 5.8.x.

=cut

