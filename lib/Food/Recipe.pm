package Food::Recipe;

# ABSTRACT: Recipe Search Tool

use Dancer qw( :syntax );
use Dancer::Cookies;
use File::Find::Rule;
use List::Util qw( all );
use lib map { "$ENV{HOME}/sandbox/$_/lib" } qw(Math-FractionManip);
use Math::FractionManip;
use MealMaster;
use Storable;
use URI::Encode qw( uri_encode );

our $VERSION = '0.05';

my $COOKIE_SEP = qr/\s*\|\s*/;
my $APP_TITLE  = 'Recipe Search Tool';

=head1 DESCRIPTION

A C<Food::Recipe> instance is a L<Dancer> search tool web GUI.

=head1 ROUTES

=head2 /

The main page with searching interface.

=cut

any '/' => sub {
    # Load the form variables
    my $title      = params->{title};
    my $category   = params->{category};
    my $ingredient = params->{ingredient};

    # If the category contains a ", assume we are looking for an exact match
    my $exact_cat = 0;
    if ( $category && $category =~ /"/ ) {
        $exact_cat = 1;
        $category =~ s/"//g;
    }

    # Turn multi-word strings into lists
    $title      = [ split /\s+/, $title ] if $title;
    $category   = [ split /\s+/, $category ] if $category;
    $ingredient = [ split /\s+/, $ingredient ] if $ingredient;

    # Load the recipes
    my @recipes = import_mm(); 

    my @matched;

    # Filter the recipes
    RECIPE: for my $recipe ( @recipes ) {
        # Title support
        if ( $title && @$title ) {
            if ( not all { $recipe->title =~ /\Q$_\E/i } @$title ) {
                next RECIPE;
            }
        }

        # Category support
        if ( $category && @$category ) {
            if ( $exact_cat ) {
                my $cat = join ' ', @$category;
                my $found = 0;
                for my $c ( @{ $recipe->categories } ) {
                    if ( lc($c) eq lc($cat) ) {
                        $found = 1;
                        last;
                    }
                }
                next RECIPE unless $found;
            }
            else {
                for my $c ( @$category ) {
                    next RECIPE unless grep { $_ =~ /\Q$c\E/i } @{ $recipe->categories };
                }
            }
        }

        # Ingredient support
        if ( $ingredient && @$ingredient ) {
            for my $i ( @$ingredient ) {
                next RECIPE unless grep { $_->product =~ /\Q$i\E/i } @{ $recipe->ingredients };
            }
        }

        # If we have made it this far, populate our matches
        push @matched, {
            title       => $recipe->title,
            categories  => $recipe->categories,
            yield       => $recipe->yield,
            ingredients => join( ', ', map { $_->product } @{ $recipe->ingredients } ),
        };
    }

    my $list = _cookies_as_arrayref();

    template 'index' => {
        page_title => $APP_TITLE,
        title      => $title,
        category   => $category,
        ingredient => $ingredient,
        matched    => \@matched,
        total      => scalar(@recipes),
        list       => $list,
    };
};

=head2 /categories

The category list page.

=cut

get '/categories' => sub {
    # Load the recipes
    my @recipes = import_mm(); 

    my %categories;

    # Extract and normalize the categories
    for my $recipe ( @recipes ) {
        for my $cat ( @{ $recipe->categories } ) {
            $cat = lc $cat;
            $categories{$cat}++;
        }
    }

    template 'categories' => {
        page_title => $APP_TITLE,
        categories => \%categories,
    };
};

=head2 /recipe

The recipe detail page with list sidebar.

=cut

any '/recipe' => sub {
    # Load the form variables
    my $title    = params->{title} or die 'No title provided';
    my $category = params->{category};
    my $yield    = params->{yield};

    my $ingredients;

    # Load the recipes
    my @recipes = import_mm(); 

    my @matches = grep { lc($_->title) eq lc($title) } @recipes;
    my @match;
    for my $recipe ( @matches ) {
        my $cat = join ' ', @{ $recipe->categories };
        next if lc($category) ne lc($cat);
        push @match, $recipe;
    }

    # Convert the number of servings
    if ( $yield ) {
        my ($number) = split( / /, $match[0]->yield );
        my $factor = $yield / $number;

        for my $i ( @{ $match[0]->ingredients } ) {
            # Make sure the quantity is an arithmetic expression
            my $quantity = $i->quantity;
            if ( $quantity ) {
                $quantity =~ s/ /+/;
                $quantity = eval $quantity;
                $quantity *= $factor;

                # Handle a quantity with a fractional part
                if ( $quantity =~ /\./ ) {
                    my @parts   = split( /\./, $quantity );
                    my $integer = $parts[0] eq '0' ? '' : "$parts[0] ";
                    my $decimal = "0.$parts[1]";

                    # Handle the broken behavior of Math::Fraction
                    $quantity = sprintf '%.2f', $quantity if length($decimal) > 8;

                    # Handle the broken behavior of Math::Fraction
                    $decimal = sprintf '%.2f', $decimal if length($decimal) > 8;
                    $decimal = eval { Math::FractionManip->new($decimal) };
                    die "Can't Math::FractionManip->new($decimal): $@" if $@;

                    $quantity = $quantity . " ($integer$decimal)";
                }
            }

            # Keep a list of converted ingredients to display
            push @$ingredients, {
                quantity => $quantity,
                measure  => $i->measure,
                product  => $i->product,
            };
        }
    }

    # Save the recipe to display, if there is a match
    my $recipe;
    $recipe = {
        title       => $match[0]->title,
        categories  => $match[0]->categories,
        yield       => $match[0]->yield,
        ingredients => $match[0]->ingredients,
        directions  => $match[0]->directions,
    } if @match;

    my $list = _cookies_as_arrayref();

    template 'recipe' => {
        page_title  => $recipe->{title},
        recipe      => $recipe,
        yield       => $yield,
        ingredients => $ingredients,
        list        => $list,
    };
};

=head2 /add

Function to add a recipe to the list.

=cut

post '/add' => sub {
    # Load the form variables
    my $title    = params->{title} or die 'No title provided';
    my $category = params->{category};

    # Add the item to the shopping list
    _add_remove_cookies( $title, 1 );

    redirect '/recipe?title=' . $title . '&category=' . $category;
    halt;
};

=head2 /clear

Function to clear the list.

=cut

post '/clear' => sub {
    # Load the form variables
    my $title    = params->{title} or die 'No title provided';
    my $category = params->{category};

    # Clear the shopping list
    cookie( list => '' );

    redirect '/recipe?title=' . $title . '&category=' . $category;
    halt;
};

=head2 /remove

Function to remove a recipe from the list.

=cut

post '/remove' => sub {
    # Load the form variables
    my $title = params->{title} or die 'No title provided';

    # Remove the given item from the shopping list
    _add_remove_cookies( $title, 0 );

    redirect '/list';
    halt;
};

=head2 /list

Display the collected recipes and compute the combined shopping list.

=cut

get '/list'  => sub {
    # Unit conversion dispatch table
    my $units = {
        c  => sub { return ( $_[0] * 8, 'oz' ) },           # cup
        cn => sub { return ( $_[0] * 12, 'oz' ) },          # can
        dr => sub { return ( $_[0] * 0.0016907, 'oz' ) },   # drop
        ds => sub { return ( $_[0] * 0.03125, 'oz' ) },     # dash
        pn => sub { return ( $_[0] * 0.013, 'oz' ) },       # pinch
        pt => sub { return ( $_[0] * 16, 'oz' ) },          # pint
        tb => sub { return ( $_[0] * 0.5, 'oz' ) },         # tablespoon
        ts => sub { return ( $_[0] * 0.167, 'oz' ) },       # teaspoon
        T  => sub { return ( $_[0] * 0.5, 'oz' ) },         # tablespoon
        t  => sub { return ( $_[0] * 0.167, 'oz' ) },       # teaspoon
    };

    # Load the recipes
    my @recipes = import_mm(); 

    my $list = _cookies_as_arrayref();

    my @items;

    # Find the given recipe by title
    for my $i ( @$list ) {
        RECIPE: for my $recipe ( @recipes ) {
            if ( uri_encode( $recipe->title ) eq $i ) {
                push @items, $recipe;
                last RECIPE;
            }
        }
    }

    # Calculate quantities and convert units
    my $items = {};
    for my $recipe ( @items ) {
        for my $ingredient ( @{ $recipe->ingredients } ) {
            my $measure  = $ingredient->measure || 'ea';
            my $quantity = $ingredient->quantity;
            $quantity =~ s/ /+/;
            $quantity = 1 unless $quantity;
            $quantity = eval $quantity;

            if ( exists $units->{$measure} ) {
                # Convert units
                ( $quantity, $measure ) = $units->{$measure}->($quantity);
            }

            push @{ $items->{ $ingredient->product } }, {
                measure  => $measure,
                quantity => $quantity,
            };
        }
    }

    # Consolidate ingredients of the same unit
    my $shop;
    for my $item ( keys %$items ) {
        my $measure;
        my $quantity = 0;
        for my $ingredient ( @{ $items->{$item} } ) {
            $measure = $ingredient->{measure};
            $quantity += $ingredient->{quantity};
        }

        $quantity = sprintf '%.2f', $quantity if length($quantity) > 8;

        $shop->{$item} = {
            measure  => $measure,
            quantity => $quantity,
        };
    }

    template 'list' => {
        page_title => $APP_TITLE,
        list => \@items,
        shop => $shop,
    };
};

=head2 /help

Display the help page.

=cut

get '/help' => sub {
    template 'help' => {
        page_title => $APP_TITLE,
    };
};

=head1 FUNCTIONS

=head2 import_mm()

Import the L<MealMaster> recipes.

=cut

sub import_mm {
    my $recipes;
    my $file = 'recipes.dat';

    if ( -e $file ) {
        $recipes = retrieve $file;
    }
    else {
        my $mm = MealMaster->new();

        my @files = File::Find::Rule->file()->in('public/MMF');

        $recipes = [ map { $mm->parse($_) } @files ];

        store $recipes, $file;
    }

    return @$recipes; 
}

sub _cookies_as_arrayref {
    my $list = cookie('list');
    $list = [ split /$COOKIE_SEP/, $list ]
        if $list;
    return $list;
}

sub _add_remove_cookies {
    my ( $title, $flag ) = @_;

    my $list = cookie('list');
    my %list;
    if ( $list || $title ) {
        @list{ split /$COOKIE_SEP/, $list } = undef;

        if ( $flag ) {
            # Add the item to the shopping list
            $list{$title} = undef;
        }
        else {
            # Remove item from shopping list
            delete $list{$title};
        }

        cookie( list => join( '|', keys %list ) );
    }
}

true;

__END__

=head1 SEE ALSO

L<Dancer>

L<Dancer::Cookies>

L<File::Find::Rule>

L<List::Util>

L<Math::FractionManip>

L<MealMaster>

L<Storable>

L<URI::Encode>

L<http://www.ffts.com/recipes.htm>

=head1 AUTHOR
 
Gene Boggs <gene@cpan.org>
 
=head1 COPYRIGHT AND LICENSE
 
This software is copyright (c) 2019 by Gene Boggs.
 
This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
 
=cut
