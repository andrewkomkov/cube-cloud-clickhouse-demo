-- Customers: 2,000,000. customer_id grows with signup_date, so the set of customers
-- who exist on a given day is a prefix of the id range (used by 03_facts.sql).
INSERT INTO demo.customers
WITH
    2000000 AS n,
    [('United States','New York','North America'), ('United States','Los Angeles','North America'),
     ('United States','Chicago','North America'), ('United States','Austin','North America'),
     ('United States','Seattle','North America'), ('Canada','Toronto','North America'),
     ('Canada','Vancouver','North America'), ('United Kingdom','London','Europe'),
     ('United Kingdom','Manchester','Europe'), ('Germany','Berlin','Europe'),
     ('Germany','Munich','Europe'), ('France','Paris','Europe'), ('Netherlands','Amsterdam','Europe'),
     ('Spain','Madrid','Europe'), ('Italy','Milan','Europe'), ('Sweden','Stockholm','Europe'),
     ('Brazil','São Paulo','Latin America'), ('Mexico','Mexico City','Latin America'),
     ('Japan','Tokyo','Asia Pacific'), ('Australia','Sydney','Asia Pacific'),
     ('Singapore','Singapore','Asia Pacific'), ('India','Bengaluru','Asia Pacific'),
     ('United Arab Emirates','Dubai','Middle East & Africa'), ('South Africa','Cape Town','Middle East & Africa')] AS geo,
    [14, 9, 6, 4, 4, 5, 3, 9, 3, 6, 3, 5, 3, 3, 2, 2, 4, 3, 3, 3, 2, 2, 1.5, 1] AS geo_w,
    ['Olivia','Liam','Emma','Noah','Ava','Lucas','Mia','Leo','Sofia','Elias','Amara','Kenji',
     'Priya','Mateo','Chloe','Hugo','Isla','Omar','Freya','Diego','Hana','Felix','Zoe','Arjun',
     'Lena','Marco','Nora','Theo','Yara','Sven'] AS first_names,
    ['Smith','Garcia','Müller','Martin','Rossi','Silva','Tanaka','Kumar','Brown','Dubois',
     'Johansson','Novak','Lopez','Wilson','Schmidt','Costa','Sato','Patel','Evans','Moreau',
     'Larsen','Walker','Fischer','Romero','Clarke','Okafor','Ivanova','Nguyen','Hughes','Berg'] AS last_names,
    number + 1 AS id,
    cd_pick(geo, geo_w, cd_u(id, 'geo')) AS g,
    first_names[1 + cityHash64(id, 'fn') % length(first_names)] AS fn,
    last_names[1 + cityHash64(id, 'ln') % length(last_names)] AS ln
SELECT
    toUInt32(id),
    concat(fn, ' ', ln),
    lower(concat(fn, '.', ln, toString(id), '@example.com')),
    toDate('2022-01-01') + toUInt32(floor(sqrt(number / n) * 1773)),
    g.1, g.2, g.3,
    cd_pick(['Consumer', 'Consumer Plus', 'Small Business', 'Enterprise'], [72, 18, 8, 2], cd_u(id, 'seg')),
    cd_pick(['Organic Search', 'Paid Search', 'Paid Social', 'Referral', 'Email', 'Affiliate', 'Direct', 'Retail Store'],
            [22, 18, 16, 8, 5, 6, 17, 8], cd_u(id, 'acq')),
    cd_pick(['18-24', '25-34', '35-44', '45-54', '55-64', '65+'], [14, 29, 24, 16, 11, 6], cd_u(id, 'age')),
    cd_pick(['Female', 'Male', 'Non-binary', 'Undisclosed'], [51, 44, 2, 3], cd_u(id, 'gen')),
    cd_pick(['Bronze', 'Silver', 'Gold', 'Platinum'], [58, 26, 12, 4], cd_u(id, 'tier')),
    toUInt8(cd_u(id, 'optin') < 0.63)
FROM numbers(2000000);

-- Products: 25,000 across 8 categories.
INSERT INTO demo.products
WITH
    -- (category, subcategory, min price, max price, gross margin)
    [('Electronics','Smartphones',249,1399,0.18), ('Electronics','Laptops',499,2899,0.14),
     ('Electronics','Headphones',29,449,0.38), ('Electronics','Smart Home',19,329,0.34),
     ('Electronics','Cameras',189,2199,0.2), ('Apparel','Women',19,249,0.58),
     ('Apparel','Men',19,229,0.56), ('Apparel','Kids',9,89,0.52), ('Apparel','Shoes',39,259,0.48),
     ('Apparel','Accessories',9,179,0.62), ('Home & Kitchen','Furniture',79,1899,0.42),
     ('Home & Kitchen','Cookware',15,349,0.46), ('Home & Kitchen','Decor',9,199,0.6),
     ('Home & Kitchen','Bedding',25,389,0.55), ('Beauty','Skincare',8,129,0.66),
     ('Beauty','Makeup',6,79,0.68), ('Beauty','Fragrance',29,219,0.6),
     ('Sports & Outdoors','Fitness',12,1499,0.4), ('Sports & Outdoors','Cycling',29,2499,0.32),
     ('Sports & Outdoors','Camping',15,699,0.44), ('Toys & Games','Toys',7,149,0.47),
     ('Toys & Games','Board Games',15,89,0.45), ('Books & Media','Books',6,59,0.3),
     ('Grocery','Coffee & Tea',5,49,0.35)] AS cats,
    [7, 4, 7, 6, 3, 9, 7, 4, 6, 5, 3, 4, 4, 3, 5, 4, 3, 3, 2, 3, 3, 2, 6, 4] AS cat_w,
    ['Northwind', 'Aurora', 'Lumen', 'Vertex', 'Kestrel', 'Halcyon', 'Brightline', 'Copperleaf',
     'Nimbus', 'Solstice', 'Ember & Oak', 'Tidewater', 'Pinecrest', 'Atlas Supply', 'Velora',
     'Mosaic', 'Orbit', 'Fernwood', 'Zephyr', 'Marlowe'] AS brands,
    number + 1 AS id,
    cd_pick(cats, cat_w, cd_u(id, 'cat')) AS c,
    brands[1 + cityHash64(id, 'brand') % length(brands)] AS b,
    floor(c.3 + (c.4 - c.3) * pow(cd_u(id, 'price'), 2)) + 0.99 AS price
SELECT
    toUInt32(id),
    concat('NW-', leftPad(toString(id), 6, '0')),
    concat(b, ' ', c.2, ' ', ['Classic','Pro','Air','Max','Lite','Studio','Edge','One','Plus','Prime'][1 + cityHash64(id,'m') % 10],
           ' ', toString(100 + cityHash64(id, 'mn') % 900)),
    c.1, c.2, b,
    toDecimal64(price, 2),
    toDecimal64(price * (1 - c.5 * (0.8 + 0.4 * cd_u(id, 'margin'))), 2),
    toDate('2020-06-01') + toUInt32(cd_u(id, 'launch') * 2300),
    toUInt8(b = 'Northwind')
FROM numbers(25000);
